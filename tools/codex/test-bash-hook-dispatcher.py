#!/usr/bin/env python3
"""Check bash-hook-dispatcher.sh fails closed: every outcome but a clean pass must exit 2 with a reason.

Codex blocks a PreToolUse call only on exit 2 with a stderr reason, or an explicit deny; any other
exit runs the tool. So each case here that wants a block asserts exit 2 *and* a non-empty reason,
and the children are stubs whose outcome a case picks, so a verdict never depends on a real guard.

Run: python3 tools/codex/test-bash-hook-dispatcher.py
"""

import json
import os
import pathlib
import shutil
import subprocess
import tempfile
import unittest


HERE = pathlib.Path(__file__).resolve().parent
DISPATCHER = HERE / "bash-hook-dispatcher.sh"
CHILDREN = ("destructive-guard/destructive-guard.sh", "pr-create-guard/pr-create-guard.sh",
            "post-push-hygiene/post-push-hygiene.sh")
# Each stub reads STUB_<NAME> for its outcome (pass, block, mute, ask, deny, crash, garbage, context) and touches STUB_MARK_<NAME>.
STUB = """#!/usr/bin/env bash
cat >/dev/null
[ -z "${STUB_MARK_%(name)s:-}" ] || : > "${STUB_MARK_%(name)s}"
case "${STUB_%(name)s:-pass}" in
  block) echo "stub refuses" >&2; exit 2 ;;
  mute) exit 2 ;;
  ask) printf '%%s' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"confirm"}}' ;;
  deny) printf '%%s' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"no"}}' ;;
  crash) echo "boom" >&2; exit 1 ;;
  garbage) echo "not json" ;;
  context) printf '{"hookSpecificOutput":{"hookEventName":"%%s","additionalContext":"note"}}' "${STUB_EVENT:-PostToolUse}" ;;
esac
exit 0
"""
PAYLOAD = {"session_id": "s", "tool_name": "Bash", "tool_input": {"command": "ls"}}


class DispatcherTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="dispatcher-test-")
        self.hooks = os.path.join(self.tmp, "hooks")
        os.makedirs(self.hooks)
        shutil.copy(DISPATCHER, self.hooks)
        for child in CHILDREN:
            path = os.path.join(self.hooks, child)
            os.makedirs(os.path.dirname(path))
            name = os.path.basename(os.path.dirname(path)).replace("-", "_").upper()
            with open(path, "w", encoding="utf-8") as fh:
                fh.write(STUB % {"name": name})
            os.chmod(path, 0o755)

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def run_dispatcher(self, stdin, path=None, **env):
        run_env = dict(os.environ, **env)
        if path is not None:
            run_env["PATH"] = path
        return subprocess.run(["bash", os.path.join(self.hooks, "bash-hook-dispatcher.sh")], input=stdin,
                              capture_output=True, text=True, env=run_env, timeout=60)

    def event(self, name, **env):
        return self.run_dispatcher(json.dumps(dict(PAYLOAD, hook_event_name=name)), **env)

    def assert_blocks(self, proc, reason_part=""):
        self.assertEqual(proc.returncode, 2, proc.stdout + proc.stderr)
        self.assertTrue(proc.stderr.strip(), "a block without a reason runs the tool under Codex")
        self.assertIn(reason_part, proc.stderr)

    def test_a_clean_pass_exits_zero_silently(self):
        proc = self.event("PreToolUse")
        self.assertEqual((proc.returncode, proc.stdout), (0, ""), proc.stderr)

    def test_every_child_refusal_blocks(self):
        for child, outcome, reason in (("DESTRUCTIVE_GUARD", "block", "stub refuses"),
                                       ("DESTRUCTIVE_GUARD", "ask", "cannot prompt"),
                                       ("PR_CREATE_GUARD", "deny", "no"),
                                       ("PR_CREATE_GUARD", "crash", "failing closed"),
                                       ("DESTRUCTIVE_GUARD", "garbage", "cannot honour")):
            self.assert_blocks(self.event("PreToolUse", **{"STUB_" + child: outcome}), reason)

    def test_the_first_refusal_wins_and_later_children_never_run(self):
        mark = pathlib.Path(self.tmp) / "pr-create-guard-ran"
        proc = self.event("PreToolUse", STUB_DESTRUCTIVE_GUARD="deny", STUB_PR_CREATE_GUARD="block",
                          STUB_MARK_PR_CREATE_GUARD=str(mark))
        self.assert_blocks(proc, "no")
        self.assertNotIn("stub refuses", proc.stderr)
        self.assertFalse(mark.exists(), "a child after the refusal ran")

    def test_an_exit_2_without_a_reason_gets_one(self):
        self.assert_blocks(self.event("PreToolUse", STUB_DESTRUCTIVE_GUARD="mute"), "exited 2 without a reason")

    def test_context_from_two_children_is_merged(self):
        proc = self.event("PreToolUse", STUB_DESTRUCTIVE_GUARD="context", STUB_PR_CREATE_GUARD="context",
                          STUB_EVENT="PreToolUse")
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertEqual(json.loads(proc.stdout)["hookSpecificOutput"]["additionalContext"], "note\n\nnote")

    def test_a_post_tool_use_crash_is_reported_not_blocked(self):
        proc = self.event("PostToolUse", STUB_POST_PUSH_HYGIENE="crash")
        self.assertEqual(proc.returncode, 1, proc.stdout + proc.stderr)
        self.assertIn("exited 1", proc.stderr)

    def test_a_missing_child_blocks(self):
        os.remove(os.path.join(self.hooks, CHILDREN[1]))
        self.assert_blocks(self.event("PreToolUse"), "missing")

    def test_an_unreadable_event_blocks(self):
        self.assert_blocks(self.run_dispatcher(json.dumps(PAYLOAD)), "unsupported event")
        self.assert_blocks(self.event("pre_tool_use"), "unsupported event")
        self.assert_blocks(self.run_dispatcher("{" + json.dumps(dict(PAYLOAD, hook_event_name="PreToolUse"))[1:-1] + ",}"),
                           "unsupported event")
        self.assert_blocks(self.run_dispatcher(""), "unsupported event")

    def test_without_jq_it_blocks_before_reading_the_event(self):
        bindir = os.path.join(self.tmp, "bin")
        os.makedirs(bindir)
        for tool in ("bash", "cat", "dirname", "head", "mktemp", "rm"):
            found = shutil.which(tool)
            self.assertIsNotNone(found, tool)
            os.symlink(found, os.path.join(bindir, tool))
        self.assert_blocks(self.event("PreToolUse", path=bindir), "jq not on PATH")

    def test_post_tool_use_relays_context(self):
        proc = self.event("PostToolUse", STUB_POST_PUSH_HYGIENE="context")
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertEqual(json.loads(proc.stdout)["hookSpecificOutput"]["additionalContext"], "note")


if __name__ == "__main__":
    unittest.main()
