#!/usr/bin/env python3
"""Check merge-grant and destructive-guard together: a merge asks only in a turn whose prompt asked.

The two hooks share one contract, a grant file per session, so neither suite alone can see it
break. Each ask case here would answer `hard` against a guard with no grant path, which is what
keeps them from passing vacuously; the fail-closed cases pin every way a grant can be unusable.
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
HOOKS = HERE.parent / "hooks"
GRANT_HOOK = HOOKS / "merge-grant" / "merge-grant.sh"
GUARD = HOOKS / "destructive-guard" / "destructive-guard.sh"
SESSION = "session-a"
MERGE = "gh pr " + "merge 17 --squash"
REST_MERGE = "gh api -X PUT repos/o/r/pulls/17/" + "merge"
STACK_MERGE = "gh stack " + "merge"


def load_runner():
    spec = importlib.util.spec_from_file_location("run_fixtures", HERE / "run-fixtures.py")
    module = importlib.util.module_from_spec(spec)
    assert spec and spec.loader
    spec.loader.exec_module(module)
    return module


RUNNER = load_runner()


class MergeGrantTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="merge-grant-test-")
        self.grants = os.path.join(self.tmp, "grants")
        # Diagnostics redirected, or test firings land in the live corpus and inflate its counts.
        self.env = dict(
            os.environ,
            CLAUDE_MERGE_GRANT_DIR=self.grants,
            HOOK_DIAG_LOG=os.path.join(self.tmp, "blocks.log"),
            HOOK_DIAG_ALLOW_LOG=os.path.join(self.tmp, "allows.log"),
            HOOK_DIAG_ASK_LOG=os.path.join(self.tmp, "asks.log"),
        )

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def prompt(self, text, session=SESSION):
        payload = {"hook_event_name": "UserPromptSubmit", "prompt": text}
        if session is not None:
            payload["session_id"] = session
        proc = subprocess.run(["bash", str(GRANT_HOOK)], input=json.dumps(payload),
                              capture_output=True, text=True, env=self.env, timeout=10)
        self.assertEqual(proc.stderr, "")
        return RUNNER.classify(proc.returncode, proc.stdout, proc.stderr)

    def guard(self, command, session=SESSION):
        payload = {"hook_event_name": "PreToolUse", "tool_name": "Bash",
                   "tool_input": {"command": command}, "cwd": self.tmp}
        if session is not None:
            payload["session_id"] = session
        proc = subprocess.run(["bash", str(GUARD)], input=json.dumps(payload), cwd=self.tmp,
                              capture_output=True, text=True, env=self.env, timeout=10)
        verdict = RUNNER.classify(proc.returncode, proc.stdout, proc.stderr)
        reason = proc.stderr
        if verdict == "ask":
            reason = json.loads(proc.stdout)["hookSpecificOutput"]["permissionDecisionReason"]
        return verdict, reason

    def write_grant(self, body, session=SESSION):
        os.makedirs(self.grants, exist_ok=True)
        with open(os.path.join(self.grants, session + ".json"), "w", encoding="utf-8") as fh:
            fh.write(body)

    def assert_verdict(self, command, want, reason_part="", session=SESSION):
        got, reason = self.guard(command, session)
        self.assertEqual(got, want, "%s -> %s: %s" % (command, got, reason[:200]))
        if reason_part:
            self.assertIn(reason_part, reason)

    def test_without_a_grant_every_merge_form_hard_blocks(self):
        for command in (MERGE, REST_MERGE, STACK_MERGE):
            self.assert_verdict(command, "hard", "no approval path")

    def test_a_request_arms_every_form_for_one_turn(self):
        self.assertEqual(self.prompt("merge 17 please"), "ctx")
        self.assert_verdict(MERGE, "ask", "merge 17 please")
        self.assert_verdict(MERGE + " --auto", "ask")
        self.assert_verdict(REST_MERGE, "ask")
        self.assert_verdict(STACK_MERGE, "ask", "each of those must be one the user named")
        self.assertEqual(self.prompt("thanks"), "allow")
        self.assert_verdict(MERGE, "hard")

    def test_the_merge_leads_an_ask_that_carries_other_triggers(self):
        self.prompt("merge 17")
        self.assert_verdict(MERGE + " && gh run delete 5", "ask", "")
        _, reason = self.guard(MERGE + " && gh run delete 5")
        self.assertTrue(reason.startswith("gh pr merge —"), reason[:80])
        self.assertIn("ALSO: gh run delete", reason)

    def test_a_grant_never_lifts_a_hard_block(self):
        self.prompt("merge 17")
        self.assert_verdict(MERGE + " --admin", "hard", "--admin")
        self.assert_verdict(MERGE + " && git clean -fd", "hard", "git clean")

    def test_a_grant_is_scoped_to_its_session(self):
        self.prompt("merge 17")
        self.assert_verdict(MERGE, "hard", session="session-b")

    def test_fails_closed_on_every_unusable_grant(self):
        self.prompt("merge 17")
        self.assert_verdict(MERGE, "hard", session=None)
        self.write_grant(json.dumps({"expires_at": int(time.time()) - 1, "prompt": "merge 17"}))
        self.assert_verdict(MERGE, "hard")
        self.write_grant("{not json")
        self.assert_verdict(MERGE, "hard")
        self.write_grant(json.dumps({"expires_at": "soon", "prompt": "merge 17"}))
        self.assert_verdict(MERGE, "hard")
        self.write_grant(json.dumps({"expires_at": int(time.time()) + 600, "prompt": "merge 17"}))
        self.assert_verdict(MERGE, "ask", "merge 17")

    def test_a_session_id_cannot_leave_the_grant_directory(self):
        outside = os.path.join(self.tmp, "escaped.json")
        self.assertEqual(self.prompt("merge 17", session="../escaped"), "allow")
        self.assertFalse(os.path.exists(outside))
        self.write_grant(json.dumps({"expires_at": int(time.time()) + 600, "prompt": "x"}),
                         session="escaped")
        os.replace(os.path.join(self.grants, "escaped.json"), outside)
        self.assert_verdict(MERGE, "hard", session="../escaped")


if __name__ == "__main__":
    unittest.main()
