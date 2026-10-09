#!/usr/bin/env python3
"""Check metadata privacy and unchanged enforcement in isolated temporary trees."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

HOOKS = Path(__file__).resolve().parent.parent / "hooks"
MARK = "INERT_DIAGNOSTIC_MARKER"
EVENTS = ("exit", "lost_stderr_on_exit_0", "invalid_json", "splitter_missing",
          "transcript_unreadable", "derive_script_missing", "derive_produced_nothing",
          "derive_returned_no_path", "prune_failed", "unknown")
DECISIONS = ("none", "allow", "ask", "deny", "defer", "notify", "unknown")
NAMES = ("destructive-guard", "worktree-preflight", "skill-arg-substitution-guard",
         "session-log", "commit-attribution-guard", "unknown")


def bash(command):
    return {"tool_input": {"command": command}, "session_id": MARK}


class Diagnostics(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="hook-diag-test-", dir="/tmp")
        self.root = Path(self.temp.name).resolve()
        self.env = dict(os.environ, TMPDIR="/tmp", HOME=str(self.root / MARK),
                        HOOK_DIAG_LOG=str(self.root / "diag.jsonl"),
                        HOOK_DIAG_ALLOW_LOG=str(self.root / "allow.jsonl"),
                        HOOK_DIAG_ASK_LOG=str(self.root / "ask.jsonl"),
                        HOOK_DIAG_LOG_ALLOWS="1", NULL_RESULT_PROBE_LOG=str(self.root / "null.jsonl"),
                        SESSION_LOG_DIR=str(self.root / "session-logs"),
                        SESSION_LOG_LEDGER_DIR=str(self.root / "ledger"),
                        CLAUDE_MERGE_GRANT_DIR=str(self.root / "grants"),
                        PR_AUTHOR_LOOKUP="0", CLAUDE_HOOK_FIXTURE_RUN="")
        self.env.pop("HOOK_DIAG_DECISION", None)
        self.env.pop("BASH_ENV", None)

    def tearDown(self):
        self.temp.cleanup()

    def run_hook(self, path, payload, env=None, cwd=None):
        return subprocess.run(["bash", str(path)], input=payload if isinstance(payload, str) else json.dumps(payload),
                              text=True, capture_output=True, env=env or self.env,
                              cwd=cwd or self.root, timeout=15)

    def records(self, name="diag.jsonl"):
        path = self.root / name
        return [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []

    def assert_records(self):
        for name in ("diag.jsonl", "allow.jsonl", "ask.jsonl", "diag.jsonl.prev", "allow.jsonl.prev", "ask.jsonl.prev"):
            for record in self.records(name):
                self.assertEqual({"ts", "hook", "exit", "decision", "event"}, set(record))
                self.assertRegex(record["ts"], r"^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$")
                self.assertIn(record["hook"], NAMES)
                self.assertIn(record["decision"], DECISIONS)
                self.assertIn(record["event"], EVENTS)
                self.assertTrue(record["exit"] is None or type(record["exit"]) is int)
                self.assertNotIn(MARK, json.dumps(record))

    def helper_script(self, body, name="destructive-guard"):
        path = self.root / "fake.sh"
        path.write_text('set -euo pipefail\nINPUT=$(cat)\nHOOK_DIAG_NAME=' + json.dumps(name)
                        + '\nsource "$DIAG_HELPER"\n' + body)
        self.env["DIAG_HELPER"] = str(HOOKS / "_lib/hook-diag.sh")
        return path

    def test_closed_categories_and_event_detail(self):
        for decision in (*DECISIONS, MARK, "ask:" + MARK):
            path = self.helper_script('HOOK_DIAG_DECISION="$TEST_DECISION"\nhook_diag_event "$TEST_EVENT" "$TEST_DETAIL"\nexit 0\n')
            for event in (*EVENTS, MARK):
                env = dict(self.env, TEST_DECISION=decision, TEST_EVENT=event, TEST_DETAIL=MARK)
                proc = self.run_hook(path, bash(MARK), env)
                self.assertEqual((0, "", ""), (proc.returncode, proc.stdout, proc.stderr))
                record = self.records()[-1]
                self.assertEqual(event if event in EVENTS else "unknown", record["event"])
                self.assertEqual(decision if decision in DECISIONS else "unknown", record["decision"])
                self.assertIsNone(record["exit"])
        for name in (*NAMES, MARK):
            proc = self.run_hook(self.helper_script('hook_diag_event splitter_missing\n', name), bash(MARK))
            self.assertEqual(0, proc.returncode)
            self.assertEqual(name if name in NAMES else "unknown", self.records()[-1]["hook"])
        self.assert_records()

    def test_exit_stderr_and_permission_reason_are_preserved(self):
        for status in (0, 1, 2):
            path = self.helper_script('printf "%s\\n\\n" "$TEST_REASON" >&2\n'
                                      'printf \'{"hookSpecificOutput":{"permissionDecision":"ask","permissionDecisionReason":"%s"}}\\n\' "$TEST_REASON"\n'
                                      'HOOK_DIAG_DECISION=ask\nexit "$TEST_STATUS"\n')
            proc = self.run_hook(path, bash(MARK), dict(self.env, TEST_REASON=MARK, TEST_STATUS=str(status)))
            self.assertEqual(status, proc.returncode)
            self.assertEqual(MARK, json.loads(proc.stdout)["hookSpecificOutput"]["permissionDecisionReason"])
            self.assertEqual(MARK + "\n\n" if status else "", proc.stderr)
        self.assertEqual([0], [r["exit"] for r in self.records("ask.jsonl")])
        self.assertIn("lost_stderr_on_exit_0", [r["event"] for r in self.records()])
        self.assert_records()

    def test_invalid_input_contains_no_input_snippet(self):
        proc = self.run_hook(self.helper_script('exit 2\n'), "{" + MARK)
        self.assertEqual((0, "", ""), (proc.returncode, proc.stdout, proc.stderr))
        self.assertEqual("invalid_json", self.records()[0]["event"])
        self.assert_records()

    def test_log_failure_does_not_change_enforcement(self):
        for target in (self.root / "missing" / "log", self.root):
            env = dict(self.env, HOOK_DIAG_LOG=str(target), HOOK_DIAG_ALLOW_LOG=str(target),
                       HOOK_DIAG_ASK_LOG=str(target), NULL_RESULT_PROBE_LOG=str(target))
            for status in (0, 1, 2):
                script = self.helper_script('HOOK_DIAG_DECISION=ask\nhook_diag_event splitter_missing\nprintf reason >&2\nexit "$TEST_STATUS"\n')
                proc = self.run_hook(script, bash(MARK), dict(env, DIAG_HELPER=self.env["DIAG_HELPER"], TEST_STATUS=str(status)))
                self.assertEqual(status, proc.returncode)
                self.assertEqual("reason" if status else "", proc.stderr)
            proc = self.run_hook(HOOKS / "null-result-probe/null-result-probe.sh",
                                 {**bash("git diff -- " + MARK), "tool_response": {"stdout":""}}, env)
            self.assertEqual(0, proc.returncode)
            self.assertIn("NULL-RESULT PROBE", proc.stdout)
            self.assertEqual("", proc.stderr)

    def test_rotation_and_mirrors(self):
        script = self.helper_script('HOOK_DIAG_MAX_SIZE=1\nhook_diag_event splitter_missing\nhook_diag_event prune_failed\n')
        self.assertEqual(0, self.run_hook(script, bash(MARK)).returncode)
        self.assertTrue((self.root / "diag.jsonl.prev").is_file())
        repo = HOOKS.parents[3]
        for local, published in ((".claude/_lib/hook-diag.sh", "_lib/hook-diag.sh"),
                                 (".claude/hooks/destructive-guard.sh", "destructive-guard/destructive-guard.sh")):
            self.assertEqual((repo / local).read_bytes(), (HOOKS / published).read_bytes())
        self.assert_records()

    def test_null_result_categories_and_warning(self):
        cases = [
            ("git diff -- " + MARK, {}, "empty", True),
            ("git diff -- " + MARK, {"stdout":"0 matches"}, "zero", True),
            (MARK, {"stdout":"normal output"}, "has_output", False),
            (MARK, {"stdout":"normal", "backgroundTaskId":MARK}, "backgrounded", False),
            (MARK, {"stdout":"normal", "noOutputExpected":True}, "no_output_expected", False),
            ("git diff -- " + MARK + " > " + MARK, {}, "stdout_redirected", False),
            ("echo " + MARK, {}, "no_construct_empty", False),
            ("echo " + MARK, {"stdout":"0 matches"}, "no_construct_zero", False),
        ]
        for command, response, category, fired in cases:
            proc = self.run_hook(HOOKS / "null-result-probe/null-result-probe.sh",
                                 {**bash(command), "tool_response": response})
            self.assertEqual((0, ""), (proc.returncode, proc.stderr))
            self.assertEqual(fired, bool(proc.stdout))
            if fired:
                self.assertIn("NULL-RESULT PROBE", json.loads(proc.stdout)["hookSpecificOutput"]["additionalContext"])
            record = self.records("null.jsonl")[-1]
            self.assertEqual({"ts", "hook", "event"}, set(record))
            self.assertEqual({"hook":"null-result-probe", "event":category}, {k:v for k,v in record.items() if k != "ts"})
            self.assertNotIn(MARK, json.dumps(record))
        env = dict(self.env, CLAUDE_HOOK_FIXTURE_RUN="1")
        self.run_hook(HOOKS / "null-result-probe/null-result-probe.sh", {**bash("git diff -- x"), "tool_response":{}}, env)
        self.assertEqual(len(cases), len(self.records("null.jsonl")))
        invalid = self.run_hook(HOOKS / "null-result-probe/null-result-probe.sh", "{" + MARK)
        self.assertEqual((0, "", ""), (invalid.returncode, invalid.stdout, invalid.stderr))
        self.assertEqual(len(cases), len(self.records("null.jsonl")))

    def test_null_unknown_category_is_closed(self):
        source = (HOOKS / "null-result-probe/null-result-probe.sh").read_text()
        start = source.index("log_line() {")
        end = source.index("\n# Both streams count:", start)
        path = self.root / "null-logger.sh"
        path.write_text('LOG="$NULL_RESULT_PROBE_LOG"\nLOG_MAX=1048576\n' + source[start:end]
                        + '\nlog_line 1 "$TEST_CATEGORY" "$TEST_DETAIL"\n')
        proc = self.run_hook(path, "", dict(self.env, TEST_CATEGORY=MARK, TEST_DETAIL=MARK))
        self.assertEqual((0, "", ""), (proc.returncode, proc.stdout, proc.stderr))
        record = self.records("null.jsonl")[0]
        self.assertEqual({"ts", "hook", "event"}, set(record))
        self.assertEqual("unknown", record["event"])
        self.assertNotIn(MARK, json.dumps(record))

    def test_session_degradation_events_retain_no_details(self):
        tree = self.root / "degraded-hooks"
        shutil.copytree(HOOKS, tree)
        hook = tree / "session-log/session-log.sh"
        derive = tree / "session-log/session-log-derive.py"
        transcript = self.root / (MARK + ".jsonl")
        transcript.write_text("{}\n")
        payload = {"session_id":MARK, "transcript_path":str(transcript)}
        derive.unlink()
        self.assertEqual(0, self.run_hook(hook, payload).returncode)
        self.assertEqual("derive_script_missing", self.records()[-1]["event"])
        for body, event in (("import sys\nsys.stderr.write('" + MARK + "')\n", "derive_produced_nothing"),
                            ("print('{}')\n", "derive_returned_no_path")):
            derive.write_text(body)
            proc = self.run_hook(hook, payload)
            self.assertEqual((0, "", ""), (proc.returncode, proc.stdout, proc.stderr))
            self.assertEqual(event, self.records()[-1]["event"])
        bins = self.root / "bin"
        bins.mkdir()
        find = bins / "find"
        find.write_text('#!/usr/bin/env bash\nprintf "%s" "$TEST_DETAIL" >&2\nexit 1\n')
        find.chmod(0o755)
        result = {"path":str(self.root / "session-logs" / (MARK + ".md"))}
        derive.write_text("print(" + repr(json.dumps(result)) + ")\n")
        proc = self.run_hook(hook, payload, dict(self.env, PATH=str(bins) + os.pathsep + self.env["PATH"], TEST_DETAIL=MARK))
        self.assertEqual((0, "", ""), (proc.returncode, proc.stdout, proc.stderr))
        self.assertEqual("prune_failed", self.records()[-1]["event"])
        self.assert_records()

    def test_all_helper_consumers_against_uninstrumented_controls(self):
        tree = self.root / "plain-hooks"
        shutil.copytree(HOOKS, tree)
        (tree / "_lib/hook-diag.sh").write_text('hook_diag_event() { :; }\n')
        repos = self.root / "repos"
        repo = repos / MARK
        repo.mkdir(parents=True)
        subprocess.run(["git", "init", "-q", "-b", "topic", str(repo)], check=True, capture_output=True)
        self.env["WORKTREE_GUARD_ROOT"] = str(repos)
        transcript = self.root / (MARK + ".jsonl")
        transcript.write_text("".join(json.dumps({"type":"user", "promptSource":"typed", "message":{"content":MARK}}) + "\n" for _ in range(5)))
        cases = [
            ("destructive-guard", bash("git status"), False),
            ("destructive-guard", bash("git push origin main"), True),
            ("destructive-guard", bash("kubectl delete pod " + MARK), True),
            ("worktree-preflight", bash("git status"), False),
            ("worktree-preflight", bash("git add " + MARK), True),
            ("skill-arg-substitution-guard", {"tool_input":{"file_path":MARK + "/SKILL.md", "content":"safe text"}}, False),
            ("skill-arg-substitution-guard", {"tool_input":{"file_path":MARK + "/SKILL.md", "content":"awk $1 " + MARK}}, True),
            ("commit-attribution-guard", bash('git commit -m "plain"'), False),
            ("commit-attribution-guard", bash('git commit -m "Co-Authored-By: ' + 'Claude ' + MARK + '"'), True),
            ("session-log", {"session_id":MARK, "transcript_path":str(self.root / MARK)}, False),
            ("session-log", {"session_id":MARK, "transcript_path":str(transcript)}, True),
        ]
        for name, payload, fires in cases:
            path = Path(name) / (name + ".sh")
            actual = self.run_hook(HOOKS / path, payload, cwd=repo)
            expected = self.run_hook(tree / path, payload, cwd=repo)
            self.assertEqual((expected.returncode, expected.stdout, expected.stderr),
                             (actual.returncode, actual.stdout, actual.stderr), name)
            self.assertEqual(fires, bool(actual.stdout or actual.stderr), name)
        self.assert_records()


if __name__ == "__main__":
    unittest.main()
