#!/usr/bin/env python3
"""Assert each hook's exit code AND which stream carried its payload.

Usage: probe-hooks.py [--hooks-dir DIR] [--only SUBSTRING] [--selftest] [-v]

Companion to run-fixtures.py, which covers one hook deeply from a TSV. This covers
the whole set shallowly on the axis that actually breaks: delivery.

A hook can be individually correct and collectively unarmed, because the harness
discards the stream it wrote to. An exit-code-only assertion scores every one of
those as passing — which is exactly how a suite stays green while the guards it
covers deliver nothing to anyone.

Three delivery contracts, each of which silently voids a whole tier:

    exit 1  is NOT a block. Claude Code prints a hook-error notice and runs the
            tool anyway. Only exit 2 blocks.
    exit 0  discards stderr outright — not shown to Claude, not to the user, not
            in the transcript. A nudge written there reaches no one.
    stdout  is added to context only on UserPromptSubmit, UserPromptExpansion and
            SessionStart. Everywhere else bare stdout goes to the debug log, so a
            PreToolUse/PostToolUse hook must wrap its payload in hookSpecificOutput.

INVARIANTS encodes those three as assertions that hold for every hook, so a new one
breaking a contract fails here without anybody adding a case for it. CASES pin the
specific behaviours worth naming — state-free ones only, since this harness
builds no repo. A hook whose verdict depends on git state belongs in a TSV fixture
with a `#!setup`, where the state is constructed rather than inherited.

`--selftest` proves each invariant fires, against hooks written to break it. An
invariant never observed to fail is indistinguishable from one that cannot.

Limitation, stated so it is not mistaken for coverage: a hook that redirects its own
FD 2 and re-emits selectively — as hook-diag.sh does — hides a stray exit-0 stderr
write from this harness. The invariant still binds it through hook-diag's own
re-emit rule, but it is directly observable only for uninstrumented hooks.
"""

import argparse
import json
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile

HERE = pathlib.Path(__file__).resolve().parent

# Assembled: a comment-discipline guard reads Edit/Write content, so a literal run blocks this file.
HASH = "#"
COMMENT_BLOCK = "\n".join([
    HASH + " rationale line one, which is prose and not a pointer",
    HASH + " rationale line two, continuing the same thought",
    "value = 1",
])
PUSH = "git push" + " origin main"
HEREDOC_BODY = "cat <<EOF > notes.md\n" + PUSH + "\nEOF"


def bash(cmd):
    return {"tool_name": "Bash", "tool_input": {"command": cmd}}


def write(path, content):
    return {"tool_name": "Write", "tool_input": {"file_path": path, "content": content}}


def post(cmd, stdout):
    # tool_response, not tool_result: a hook reading the latter gets "" for every command.
    return {"tool_name": "Bash", "tool_input": {"command": cmd},
            "tool_response": {"stdout": stdout, "stderr": "", "interrupted": False}}


# (name, hook, event, payload, want_exit, want_channel)
CASES = [
    ("destructive-guard hard-blocks a push to main",
     "destructive-guard", "PreToolUse", bash("git push origin main"), 2, "stderr"),
    ("destructive-guard blocks the force spelling too",
     "destructive-guard", "PreToolUse", bash("git push --force origin main"), 2, "stderr"),
    ("destructive-guard leaves an ordinary command alone",
     "destructive-guard", "PreToolUse", bash("git status"), 0, "silent"),
    ("destructive-guard ignores its trigger inside a message body",
     "destructive-guard", "PreToolUse",
     bash('git commit -m "docs: never git push origin main directly"'), 0, "silent"),
    ("pr-create-guard ignores an unrelated command",
     "pr-create-guard", "PreToolUse", bash("ls -la"), 0, "silent"),
    ("stateful-op-reminder delivers as context, never stderr",
     "stateful-op-reminder", "PreToolUse",
     bash("kubectl apply -f deploy.yaml"), 0, "context-free"),
    ("stateful-op-reminder stays silent on a read",
     "stateful-op-reminder", "PreToolUse", bash("kubectl get pods"), 0, "silent"),
    ("a heredoc body does not smuggle a trigger past the guard",
     "destructive-guard", "PreToolUse", bash(HEREDOC_BODY), 0, "silent"),
    ("stateful-op-reminder ignores its trigger in a message body",
     "stateful-op-reminder", "PreToolUse",
     bash('git commit -m "chore: stop running kubectl apply by hand"'), 0, "silent"),
]


def classify(rc, stdout, stderr):
    if stderr.strip():
        return "stderr"
    if not stdout.strip():
        return "silent"
    try:
        obj = json.loads(stdout)
    except ValueError:
        return "stdout-raw"
    if not isinstance(obj, dict):
        return "stdout-raw"
    hso = obj.get("hookSpecificOutput") or {}
    if "permissionDecision" in hso:
        return hso["permissionDecision"]
    if "additionalContext" in hso:
        return "context"
    if "updatedInput" in hso:
        return "rewrite"
    if obj.get("decision") == "block":
        return "block"
    return "stdout-raw"


def invariants(event, rc, stdout, stderr):
    """Contract violations that hold for every hook, case expectations aside."""
    bad = []
    if rc == 1:
        bad.append("exit 1 does not block - use exit 2 to block or exit 0 to advise")
    if rc == 2 and not stderr.strip():
        bad.append("exit 2 discards stdout - the block reason must go to stderr")
    if rc == 0 and stderr.strip():
        bad.append("exit 0 discards stderr - this message reaches no one")
    if rc == 0 and stdout.strip() and event in ("PreToolUse", "PostToolUse"):
        try:
            json.loads(stdout)
        except ValueError:
            bad.append("bare stdout on %s goes to the debug log - wrap it in "
                       "hookSpecificOutput" % event)
    return bad


def resolve_hook(hooks_dir, name):
    for candidate in (hooks_dir / ("%s.sh" % name), hooks_dir / name / ("%s.sh" % name)):
        if candidate.is_file():
            return candidate
    return None


def run(path, event, payload, cwd, env, timeout=15.0):
    body = dict(payload)
    body.setdefault("session_id", "probe")
    body.setdefault("cwd", cwd)
    body["hook_event_name"] = event
    try:
        proc = subprocess.run(["bash", str(path)], input=json.dumps(body),
                              capture_output=True, text=True, cwd=cwd,
                              timeout=timeout, env=env)
        return proc.returncode, proc.stdout, proc.stderr
    except subprocess.TimeoutExpired:
        return -1, "", ""


SELFTESTS = [
    ("exit 1 is flagged as non-blocking",
     'echo "reason" >&2\nexit 1\n', "exit 1 does not block"),
    ("exit 2 without stderr is flagged",
     'echo "reason on stdout"\nexit 2\n', "the block reason must go to stderr"),
    ("exit 0 with stderr is flagged",
     'echo "advice nobody receives" >&2\nexit 0\n', "exit 0 discards stderr"),
    ("bare stdout on PreToolUse is flagged",
     'echo "context that goes to the debug log"\nexit 0\n', "wrap it in hookSpecificOutput"),
]


def selftest(env):
    """Prove each invariant fires; one never observed to fail cannot be trusted."""
    tmp = tempfile.mkdtemp(prefix="probe-selftest-")
    failures = 0
    try:
        for name, body, want in SELFTESTS:
            path = os.path.join(tmp, "fake.sh")
            with open(path, "w", encoding="utf-8") as fh:
                fh.write("#!/usr/bin/env bash\ncat >/dev/null\n" + body)
            rc, out, err = run(path, "PreToolUse", bash("x"), tmp, env)
            broken = invariants("PreToolUse", rc, out, err)
            hit = any(want in b for b in broken)
            print("%s %-46s %s" % ("ok  " if hit else "FAIL", name[:46],
                                   "caught" if hit else "NOT CAUGHT: %s" % broken))
            if not hit:
                failures += 1
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    print("\n%d/%d invariants proven non-vacuous" % (len(SELFTESTS) - failures, len(SELFTESTS)))
    return failures


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--hooks-dir", default=str(HERE.parent))
    ap.add_argument("--only", default="", help="run cases whose name contains this")
    ap.add_argument("--selftest", action="store_true",
                    help="prove each contract invariant actually fires")
    ap.add_argument("-v", "--verbose", action="store_true")
    args = ap.parse_args()

    # Redirected, or probe runs land in the live corpus and inflate its counts.
    tmp = tempfile.mkdtemp(prefix="probe-hooks-")
    env = dict(os.environ,
               HOOK_DIAG_LOG=os.path.join(tmp, "blocks.log"),
               HOOK_DIAG_ALLOW_LOG=os.path.join(tmp, "allows.log"),
               HOOK_DIAG_ASK_LOG=os.path.join(tmp, "asks.log"))

    if args.selftest:
        rc = selftest(env)
        shutil.rmtree(tmp, ignore_errors=True)
        sys.exit(1 if rc else 0)

    hooks_dir = pathlib.Path(args.hooks_dir).expanduser().resolve()
    cases = [c for c in CASES if args.only.lower() in c[0].lower()] if args.only else CASES

    failures, skipped = [], []
    try:
        for name, hook, event, payload, want_exit, want_chan in cases:
            path = resolve_hook(hooks_dir, hook)
            if path is None:
                skipped.append((name, hook))
                print("skip %-46s (no %s under %s)" % (name[:46], hook, hooks_dir))
                continue
            rc, out, err = run(path, event, payload, str(hooks_dir), env)
            got = classify(rc, out, err)
            if want_chan == "context-free":
                # May pass silently or with context, but must not flag.
                ok = rc == want_exit and got in ("silent", "context")
            else:
                ok = rc == want_exit and got == want_chan
            broken = invariants(event, rc, out, err)
            if broken:
                ok = False
            if not ok:
                failures.append((name, want_exit, want_chan, rc, got, broken))
            print("%s %-46s want=%d/%-13s got=%d/%s"
                  % ("ok  " if ok else "FAIL", name[:46], want_exit, want_chan, rc, got))
            for b in broken:
                print("       CONTRACT: %s" % b)
            if args.verbose and out.strip():
                print("       stdout: %s" % out.strip()[:160])
            if args.verbose and err.strip():
                print("       stderr: %s" % err.strip()[:160])
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    ran = len(cases) - len(skipped)
    print("\n%d/%d passed (%d skipped)" % (ran - len(failures), ran, len(skipped)))
    if failures:
        print("\n%d FAILURES:" % len(failures))
        for name, we, wc, rc, got, broken in failures:
            print("  %s: want=%d/%s got=%d/%s" % (name, we, wc, rc, got))
            for b in broken:
                print("    contract: %s" % b)
        sys.exit(1)


if __name__ == "__main__":
    main()
