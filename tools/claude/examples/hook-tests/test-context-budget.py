#!/usr/bin/env python3
"""Check the context-budget pair together: the statusline writes the flag, the Stop hook acts on it.

The two scripts share one contract, a flag file per session, so neither alone can see it break.
Every block case would answer `allow` against a statusline that never writes the flag, which is
what keeps the stop cases from passing vacuously.
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
STATUSLINE = HOOKS / "statusline" / "statusline-command.sh"
STOP = HOOKS / "context-budget-stop" / "context-budget-stop.sh"


def load(name, filename):
    spec = importlib.util.spec_from_file_location(name, HERE / filename)
    module = importlib.util.module_from_spec(spec)
    assert spec and spec.loader
    spec.loader.exec_module(module)
    return module


RUNNER = load("run_fixtures", "run-fixtures.py")
PROBE = load("probe_hooks", "probe-hooks.py")


class ContextBudgetTest(unittest.TestCase):
    def setUp(self):
        self.tmp = pathlib.Path(tempfile.mkdtemp(prefix="context-budget-test-"))
        self.flags = self.tmp / "flags"
        self.notified = self.tmp / "notified.log"
        stubs = self.tmp / "bin"
        stubs.mkdir()
        # Both notifiers stubbed, so the suite records instead of posting on any platform.
        for name in ("osascript", "notify-send"):
            stub = stubs / name
            stub.write_text(f'#!/bin/sh\necho "$@" >> "{self.notified}"\n')
            stub.chmod(0o755)
        self.env = dict(os.environ, HOME=str(self.tmp), CLAUDE_CONTEXT_BUDGET_DIR=str(self.flags),
                        PATH=f"{stubs}:{os.environ.get('PATH', '/usr/bin:/bin')}")
        self.env.pop("CLAUDE_CONTEXT_BUDGET_TOKENS", None)

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def statusline(self, sid, pct, size, cap=None):
        payload = {"session_id": sid, "model": {"display_name": "Model"},
                   "workspace": {"current_dir": str(self.tmp)},
                   "context_window": {"used_percentage": pct, "context_window_size": size}}
        env = dict(self.env)
        if cap is not None:
            env["CLAUDE_CONTEXT_BUDGET_TOKENS"] = str(cap)
        proc = subprocess.run(["bash", str(STATUSLINE)], input=json.dumps(payload),
                              capture_output=True, text=True, env=env, timeout=30, check=False)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        return proc.stdout

    def flag(self, sid):
        path = self.flags / sid
        return path.read_text().split() if path.exists() else None

    def stop(self, payload):
        body = json.dumps(payload) if isinstance(payload, dict) else payload
        proc = subprocess.run(["bash", str(STOP)], input=body, capture_output=True,
                              text=True, env=self.env, timeout=30, check=False)
        self.assertEqual(PROBE.invariants("Stop", proc.returncode, proc.stdout, proc.stderr), [])
        return RUNNER.classify(proc.returncode, proc.stdout, proc.stderr, "Stop"), proc.stdout

    def notes(self):
        # The notifier is backgrounded, so give it a moment to land.
        deadline = time.time() + 5
        while time.time() < deadline and not self.notified.exists():
            time.sleep(0.05)
        time.sleep(0.2)
        return self.notified.read_text().splitlines() if self.notified.exists() else []

    def test_default_budget_is_three_quarters_of_the_window(self):
        self.statusline("under", 74, 200_000)
        self.statusline("over", 76, 200_000)
        self.assertIsNone(self.flag("under"))
        self.assertEqual(self.flag("over"), ["152000", "150000"])

    def test_env_cap_lowers_the_budget(self):
        self.statusline("capped", 51, 1_000_000, cap=500_000)
        self.statusline("below-cap", 49, 1_000_000, cap=500_000)
        self.assertEqual(self.flag("capped"), ["510000", "500000"])
        self.assertIsNone(self.flag("below-cap"))

    def test_env_cap_never_raises_the_budget_past_three_quarters(self):
        self.statusline("raised", 76, 200_000, cap=900_000)
        self.assertEqual(self.flag("raised"), ["152000", "150000"])

    def test_invalid_cap_falls_back_to_the_default(self):
        for i, cap in enumerate(("abc", "0", "-5")):
            sid = f"bad-cap-{i}"
            self.statusline(sid, 76, 200_000, cap=cap)
            self.assertEqual(self.flag(sid), ["152000", "150000"], cap)

    def test_over_budget_turns_the_segment_red(self):
        out = self.statusline("red", 51, 1_000_000, cap=500_000)
        self.assertIn("\x1b[31mctx:51%", out)

    def test_unusable_identity_writes_no_flag(self):
        self.statusline("../escape", 90, 200_000)
        self.statusline("no-size", 90, "")
        self.assertFalse(self.flags.exists() and any(self.flags.iterdir()))
        self.assertFalse((self.tmp / "escape").exists())

    def test_one_notification_per_flagged_session(self):
        self.statusline("a", 80, 200_000)
        self.statusline("a", 85, 200_000)
        self.statusline("b", 80, 200_000)
        self.assertEqual(len(self.notes()), 2)

    def test_stop_without_flag_allows(self):
        self.assertEqual(self.stop({"session_id": "none", "stop_hook_active": False})[0], "allow")

    def test_stop_blocks_once_then_allows(self):
        self.statusline("s", 51, 1_000_000, cap=500_000)
        outcome, out = self.stop({"session_id": "s", "stop_hook_active": False})
        self.assertEqual(outcome, "block")
        reason = json.loads(out)["reason"]
        self.assertIn("~510k", reason)
        self.assertIn("500k budget", reason)
        self.assertIn("read <path> and continue", reason)
        self.assertEqual(self.stop({"session_id": "s", "stop_hook_active": False})[0], "allow")

    def test_stop_hook_active_defers_without_consuming_the_flag(self):
        self.statusline("chained", 80, 200_000)
        self.assertEqual(self.stop({"session_id": "chained", "stop_hook_active": True})[0], "allow")
        self.assertFalse((self.flags / "chained.handled").exists())
        self.assertEqual(self.stop({"session_id": "chained", "stop_hook_active": False})[0], "block")

    def test_unreadable_input_allows(self):
        self.statusline("present", 80, 200_000)
        for payload in ("", "not json", {"stop_hook_active": False}, {"session_id": "../present"}):
            self.assertEqual(self.stop(payload)[0], "allow", payload)

    def test_corrupt_flag_still_blocks_once(self):
        self.flags.mkdir()
        (self.flags / "corrupt").write_text('x"y\n')
        outcome, out = self.stop({"session_id": "corrupt"})
        self.assertEqual(outcome, "block")
        self.assertIn("~0k", json.loads(out)["reason"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
