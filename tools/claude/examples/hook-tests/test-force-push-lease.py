#!/usr/bin/env python3
"""Check destructive-guard's own-PR lease: which force-pushes run without a prompt.

The exemption reads live state — the commits the lease would overwrite, and who opened the
branch's PR — so a command-only fixture cannot exercise it. Each case builds that state: a real
repository whose origin is a GitHub URL, and a `gh` on PATH that answers the two lookups. Every
`allow` here would answer `ask` against a guard without the exemption, and every other case pins
one input that must keep the prompt.
"""

import importlib.util
import json
import os
import pathlib
import shutil
import subprocess
import tempfile
import time
import unittest


HERE = pathlib.Path(__file__).resolve().parent
GUARD = HERE.parent / "hooks" / "destructive-guard" / "destructive-guard.sh"
ME = "me@example.com"
# `pr list` answers only for GH_REPO and applies the caller's own --jq, so the filter itself is under test.
GH_STUB = """#!/usr/bin/env bash
case "$*" in
  "api user"*) printf '%s\\n' "${GH_SELF:-}" ;;
  "pr list --repo ${GH_REPO:-example/repo} "*)
    [ -z "${GH_SLEEP:-}" ] || { sleep "$GH_SLEEP"; printf '%s\\n' "${GH_PR_AUTHOR:-}"; exit 0; }
    filter=""
    while [ $# -gt 0 ]; do [ "$1" = --jq ] && filter=$2; shift; done
    {
      for a in ${GH_PR_AUTHOR:-}; do printf '{"author":{"login":"%s"},"isCrossRepository":false}\\n' "$a"; done
      for a in ${GH_FORK_AUTHOR:-}; do printf '{"author":{"login":"%s"},"isCrossRepository":true}\\n' "$a"; done
    } | jq -s -r "$filter" ;;
esac
exit "${GH_EXIT:-0}"
"""


def load_runner():
    spec = importlib.util.spec_from_file_location("run_fixtures", HERE / "run-fixtures.py")
    module = importlib.util.module_from_spec(spec)
    assert spec and spec.loader
    spec.loader.exec_module(module)
    return module


RUNNER = load_runner()


class OwnPrLeaseTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="force-push-lease-test-")
        bindir = os.path.join(self.tmp, "bin")
        os.makedirs(bindir)
        stub = os.path.join(bindir, "gh")
        with open(stub, "w", encoding="utf-8") as fh:
            fh.write(GH_STUB)
        os.chmod(stub, 0o755)
        home = os.path.join(self.tmp, "home")
        os.makedirs(home)
        # A private HOME: pr-author.sh caches the self login there, and a real cache would decide the case.
        self.env = dict(
            os.environ,
            HOME=home,
            PATH=bindir + os.pathsep + os.environ.get("PATH", ""),
            GH_SELF="me",
            GH_PR_AUTHOR="me",
            GIT_CONFIG_NOSYSTEM="1",
            CLAUDE_MERGE_GRANT_DIR=os.path.join(self.tmp, "grants"),
            HOOK_DIAG_LOG=os.path.join(self.tmp, "blocks.log"),
            HOOK_DIAG_ALLOW_LOG=os.path.join(self.tmp, "allows.log"),
            HOOK_DIAG_ASK_LOG=os.path.join(self.tmp, "asks.log"),
        )
        self.repo = os.path.join(self.tmp, "repo")
        self.git("init", "-q", "-b", "main", self.repo, cwd=self.tmp)
        self.git("config", "user.email", ME)
        self.git("config", "user.name", "Me")
        self.git("remote", "add", "origin", "https://github.com/example/repo.git")
        base = self.commit("base")
        self.git("update-ref", "refs/remotes/origin/main", base)
        self.git("checkout", "-q", "-b", "feature")
        self.commit("mine 1")
        self.mine = self.commit("mine 2")
        self.git("checkout", "-q", "-b", "shared")
        self.shared = self.commit("theirs", email="them@example.com")
        self.git("checkout", "-q", "feature")

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def git(self, *args, cwd=None):
        proc = subprocess.run(["git", *args], cwd=cwd or self.repo, env=self.env,
                              capture_output=True, text=True, check=True)
        return proc.stdout.strip()

    def commit(self, message, email=ME):
        env = dict(self.env, GIT_AUTHOR_EMAIL=email, GIT_COMMITTER_EMAIL=email)
        subprocess.run(["git", "commit", "-q", "--allow-empty", "-m", message],
                       cwd=self.repo, env=env, check=True)
        return self.git("rev-parse", "HEAD")

    def verdict(self, command, **env):
        payload = {"hook_event_name": "PreToolUse", "tool_name": "Bash", "session_id": "s",
                   "tool_input": {"command": command}, "cwd": self.repo}
        proc = subprocess.run(["bash", str(GUARD)], input=json.dumps(payload), cwd=self.repo,
                              capture_output=True, text=True, env=dict(self.env, **env), timeout=60)
        got = RUNNER.classify(proc.returncode, proc.stdout, proc.stderr)
        return got, proc.stdout + proc.stderr

    def assert_verdict(self, command, want, **env):
        got, out = self.verdict(command, **env)
        self.assertEqual(got, want, "%s -> %s: %s" % (command, got, out[:300]))

    def lease(self, ref="feature", sha=None):
        return "--force-with-lease=%s:%s" % (ref, sha or self.mine)

    def test_an_exact_lease_over_own_commits_on_own_pr_runs(self):
        self.assert_verdict("git push origin feature " + self.lease(), "allow")
        self.assert_verdict("git push " + self.lease() + " origin feature", "allow")
        self.assert_verdict("git push -u origin feature " + self.lease() + " --force-if-includes", "allow")
        self.assert_verdict("git -C %s push origin feature %s" % (self.repo, self.lease()), "allow")
        self.assert_verdict("git push origin feature " + self.lease(sha=self.mine[:12]), "allow")

    def test_every_other_force_spelling_still_asks(self):
        for command in ("git push --force origin feature",
                        "git push -f origin feature",
                        "git push origin +feature",
                        "git push --force-with-lease origin feature",
                        "git push --force-with-lease=feature origin feature",
                        "git push --force origin feature " + self.lease()):
            self.assert_verdict(command, "ask")
        self.assert_verdict("git push --mirror origin feature " + self.lease(), "hard")

    def test_the_lease_must_name_the_pushed_branch_and_origin(self):
        self.assert_verdict("git push origin feature " + self.lease(ref="other"), "ask")
        self.assert_verdict("git push upstream feature " + self.lease(), "ask")
        self.assert_verdict("git push origin feature:feature " + self.lease(), "ask")
        self.assert_verdict("git push origin feature " + self.lease(sha="0" * 40), "ask")

    def test_a_collaborators_commit_under_the_lease_keeps_the_prompt(self):
        self.assert_verdict("git push origin shared " + self.lease(ref="shared", sha=self.shared), "ask")

    def test_someone_elses_pr_or_no_pr_keeps_the_prompt(self):
        self.assert_verdict("git push origin feature " + self.lease(), "ask", GH_PR_AUTHOR="them")
        self.assert_verdict("git push origin feature " + self.lease(), "ask", GH_PR_AUTHOR="")
        self.assert_verdict("git push origin feature " + self.lease(), "ask", GH_PR_AUTHOR="me them")

    def test_every_open_pr_from_the_branch_being_yours_is_enough(self):
        self.assert_verdict("git push origin feature " + self.lease(), "allow", GH_PR_AUTHOR="me me")

    def test_a_fork_pr_with_the_same_branch_name_is_not_the_branchs_pr(self):
        self.assert_verdict("git push origin feature " + self.lease(), "ask", GH_PR_AUTHOR="", GH_FORK_AUTHOR="me")
        self.assert_verdict("git push origin feature " + self.lease(), "allow", GH_FORK_AUTHOR="them")

    def test_fails_closed_when_a_lookup_cannot_answer(self):
        self.assert_verdict("git push origin feature " + self.lease(), "ask", GH_SELF="", GH_PR_AUTHOR="")
        self.assert_verdict("git push origin feature " + self.lease(), "ask", GH_EXIT="1", GH_PR_AUTHOR="")
        self.assert_verdict("git push origin feature " + self.lease(), "ask", PR_AUTHOR_LOOKUP="0")
        self.git("remote", "set-url", "origin", "https://git.example.com/example/repo.git")
        self.assert_verdict("git push origin feature " + self.lease(), "ask")

    def test_a_second_push_in_the_command_keeps_the_prompt(self):
        self.assert_verdict("git push origin feature %s && git push --force origin other" % self.lease(), "ask")
        self.assert_verdict("git push origin :old && git push origin feature " + self.lease(), "ask")

    def test_main_stays_hard_whatever_the_lease(self):
        self.assert_verdict("git push origin main --force-with-lease=main:" + self.mine, "hard")

    def test_a_redirect_or_separator_never_carries_another_refspec_or_push_past_the_prompt(self):
        lease = "git push origin feature " + self.lease()
        self.assert_verdict(lease + " &>/dev/null +main", "hard")
        self.assert_verdict(lease + " &>/dev/null +refs/heads/*:refs/heads/*", "hard")
        self.assert_verdict(lease + " &>/dev/null +other", "ask")
        self.assert_verdict(lease + " &>/dev/null :other", "ask")
        self.assert_verdict(lease + "; git push>/dev/null -f origin other", "ask")
        self.assert_verdict(lease + "; git push>/dev/null -f origin main", "hard")
        self.assert_verdict(lease + "\ngit push>/dev/null -f origin other", "ask")
        self.assert_verdict(lease + " >/dev/null", "ask")
        self.assert_verdict(lease + " $EXTRA", "ask")
        self.assert_verdict("GIT_DIR=x " + lease, "ask")

    def test_the_lookups_read_the_repository_the_push_reaches(self):
        theirs = os.path.join(self.tmp, "theirs")
        self.git("clone", "-q", self.repo, theirs, cwd=self.tmp)
        self.git("remote", "set-url", "origin", "https://github.com/example/theirs.git", cwd=theirs)
        self.assert_verdict("cd %s && git -C %s push origin feature %s" % (self.repo, theirs, self.lease()), "ask")
        self.assert_verdict("git -c remote.origin.pushurl=https://github.com/example/theirs.git push origin feature "
                            + self.lease(), "ask")
        self.git("config", "remote.origin.pushurl", "https://github.com/example/theirs.git")
        self.assert_verdict("git push origin feature " + self.lease(), "ask")

    def test_a_hung_gh_is_bounded_and_keeps_the_prompt(self):
        started = time.monotonic()
        self.assert_verdict("git push origin feature " + self.lease(), "ask", GH_SLEEP="30", PR_AUTHOR_TIMEOUT="2")
        self.assertLess(time.monotonic() - started, 6)


if __name__ == "__main__":
    unittest.main()
