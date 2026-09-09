#!/usr/bin/env python3
"""Build the live state a repo-reading hook resolves its verdict from.

Some guards do not decide from the command string at all. They ask git what is
staged, whether the branch was pushed, whether `origin/main` resolves. Point those
at whatever happens to be in `--cwd` and the suite flaps with the day; point them
at nothing and they return at their first bail, passing every case without ever
reaching a branch. Either way the fixture asserts nothing while looking green.

A setup returns a dict with any of:

    tokens   {name: path}   substituted into fixture columns as `{name}`
    env      {name: value}  merged into the hook's environment
    cwd      str            overrides --cwd for every case in the file

Triggers are assembled from parts rather than written whole, because the commit
that adds a fixture for a phrase-matching guard is the one file guaranteed to
contain the phrase.
"""

import os
import subprocess

Q = subprocess.DEVNULL


def _git(repo, *args):
    subprocess.run(["git"] + list(args), cwd=repo, stdout=Q, stderr=Q, check=True)


def _init(path, branch="main"):
    os.makedirs(path, exist_ok=True)
    _git(path, "init", "-q", "-b", branch)
    _git(path, "config", "user.email", "fixture@example.com")
    _git(path, "config", "user.name", "fixture")
    _git(path, "config", "commit.gpgsign", "false")
    return path


def _write(repo, rel, body):
    full = os.path.join(repo, rel)
    os.makedirs(os.path.dirname(full), exist_ok=True)
    with open(full, "w", encoding="utf-8") as fh:
        fh.write(body)
    return full


def _head(repo):
    return subprocess.run(["git", "rev-parse", "HEAD"], cwd=repo, capture_output=True,
                          text=True, check=True).stdout.strip()


def _base_commit(repo):
    _write(repo, "README.txt", "base\n")
    _git(repo, "add", "-A")
    _git(repo, "commit", "-qm", "base")
    return _head(repo)


def _staged_repo(tmp, name, rel, body):
    """A repo with `rel` staged — for guards reading the index rather than the disk."""
    repo = _init(os.path.join(tmp, name))
    _base_commit(repo)
    _write(repo, rel, body)
    _git(repo, "add", "-A")
    return repo


def _pr_repo(tmp, name, *, ahead=True, pushed=True, dirty=False, origin_main=True):
    repo = _init(os.path.join(tmp, name))
    head = _base_commit(repo)
    if origin_main:
        _git(repo, "update-ref", "refs/remotes/origin/main", head)
    _git(repo, "checkout", "-q", "-b", "feature")
    if ahead:
        _write(repo, "feature.txt", "work\n")
        _git(repo, "add", "-A")
        _git(repo, "commit", "-qm", "feature")
        head = _head(repo)
    if pushed:
        _git(repo, "update-ref", "refs/remotes/origin/feature", head)
    if dirty:
        _write(repo, "scratch.txt", "uncommitted\n")
    return repo


def pr_create(tmp):
    """The five branch states a PR-creation guard has to tell apart.

    The two noorigin states split one rule in half. Neither can measure a diff, so
    neither may be blocked for that — but `noorigin` is ALSO unpushed, and that check
    needs no origin/<default> at all. A guard that skips it too has let an unresolvable
    default branch take down checks that never depended on it.
    """
    return {"tokens": {
        "zero": _pr_repo(tmp, "pr-zero", ahead=False),
        "unpushed": _pr_repo(tmp, "pr-unpushed", pushed=False),
        "dirty": _pr_repo(tmp, "pr-dirty", dirty=True),
        "ready": _pr_repo(tmp, "pr-ready"),
        "noorigin": _pr_repo(tmp, "pr-noorigin", origin_main=False, pushed=False),
        "noorigin_ready": _pr_repo(tmp, "pr-noorigin-ready", origin_main=False),
    }}


def destructive_guard(tmp):
    feature = _init(os.path.join(tmp, "push-feature"), branch="feature")
    return {"cwd": feature, "tokens": {
        "push_feature": feature,
        "push_main": _init(os.path.join(tmp, "push-main")),
        "push_master": _init(os.path.join(tmp, "push-master"), branch="master"),
    }}


def staged_workflow(tmp):
    """One repo with a broken staged workflow, one valid, one with no workflow at all."""
    bad = "on: push\njobs:\n  a:\n    runs-on: ubuntu-latest\n    steps:\n      - run:\n"
    good = ("on: push\njobs:\n  a:\n    runs-on: ubuntu-latest\n"
            "    steps:\n      - run: echo ok\n")
    return {"tokens": {
        "bad": _staged_repo(tmp, "wf-bad", ".github/workflows/broken.yaml", bad),
        "good": _staged_repo(tmp, "wf-good", ".github/workflows/ok.yaml", good),
        "nonwf": _staged_repo(tmp, "wf-none", "src/app.py", "x = 1\n"),
    }}


def gh_shim(tmp):
    """A `gh` on PATH answering without a network, so no verdict can track auth state."""
    bindir = os.path.join(tmp, "bin")
    os.makedirs(bindir, exist_ok=True)
    path = os.path.join(bindir, "gh")
    with open(path, "w", encoding="utf-8") as fh:
        fh.write('#!/usr/bin/env bash\nprintf "%s\\n" "${GH_SHIM_OUTPUT:-}"\nexit 0\n')
    os.chmod(path, 0o755)
    return {"env": {"PATH": bindir + os.pathsep + os.environ.get("PATH", "")}}


SETUPS = {
    "destructive-guard": destructive_guard,
    "pr-create": pr_create,
    "staged-workflow": staged_workflow,
    "gh-shim": gh_shim,
}
