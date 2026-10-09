#!/usr/bin/env python3
"""Pin the published harness contract without invoking a Claude client."""

import importlib.util
import json
import os
import re
from pathlib import Path
import subprocess
import tempfile
import unittest

HERE = Path(__file__).resolve().parent


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


RUNNER = load("fixtures", HERE / "run-fixtures.py")
PROBE = load("probe", HERE / "probe-hooks.py")


def nested(**fields):
    fields.setdefault("hookEventName", "PreToolUse")
    return json.dumps({"hookSpecificOutput": fields})


CASES = [
    ("empty", "PreToolUse", "", "allow"),
    ("whitespace", "PreToolUse", " \n\t", "allow"),
    ("empty object", "PreToolUse", "{}", "allow"),
    ("optional field absent", "PreToolUse", nested(hookEventName="PreToolUse"), "allow"),
    ("empty optional object", "PreToolUse", '{"hookSpecificOutput":{}}', "error"),
    ("missing event", "PreToolUse", '{"hookSpecificOutput":{"permissionDecision":"ask"}}', "error"),
    ("missing context event", "PostToolUse", '{"hookSpecificOutput":{"additionalContext":"x"}}', "error"),
    ("null event", "PreToolUse", nested(hookEventName=None), "error"),
    ("allow", "PreToolUse", nested(permissionDecision="allow"), "allow"),
    ("ask", "PreToolUse", nested(permissionDecision="ask"), "ask"),
    ("deny", "PreToolUse", nested(permissionDecision="deny"), "deny"),
    ("defer", "PreToolUse", nested(permissionDecision="defer"), "defer"),
    ("context", "PostToolUse", nested(hookEventName="PostToolUse", additionalContext="check"), "ctx"),
    ("stop", "Stop", '{"decision":"block","reason":"unfinished"}', "block"),
    ("legacy pre block", "PreToolUse", '{"decision":"block"}', "deny"),
    ("legacy approve", "PreToolUse", '{"decision":"approve"}', "allow"),
    ("post block", "PostToolUse", '{"decision":"block"}', "block"),
    ("halt", "Stop", '{"continue":false}', "halt"),
    ("system message", "Stop", '{"systemMessage":"state stale"}', "allow"),
    ("rewrite", "PreToolUse", nested(updatedInput={"command":"git status"}), "allow"),
    ("malformed", "PreToolUse", "{bad", "error"),
    ("nonempty text", "PreToolUse", "not JSON", "error"),
    ("array", "PreToolUse", "[]", "error"),
    ("null", "PreToolUse", "null", "error"),
    ("scalar", "PreToolUse", "7", "error"),
    ("string", "PostToolUse", '"text"', "error"),
    ("boolean", "Stop", "true", "error"),
    ("null hso", "PreToolUse", '{"hookSpecificOutput":null}', "error"),
    ("scalar hso", "PreToolUse", '{"hookSpecificOutput":1}', "error"),
    ("array hso", "PostToolUse", '{"hookSpecificOutput":[]}', "error"),
    ("unknown decision", "PreToolUse", nested(permissionDecision="typo"), "error"),
    ("nested block", "PreToolUse", nested(permissionDecision="block"), "error"),
    ("null decision", "PreToolUse", nested(permissionDecision=None), "error"),
    ("false decision", "PreToolUse", nested(permissionDecision=False), "error"),
    ("empty decision", "PreToolUse", nested(permissionDecision=""), "error"),
    ("post permission", "PostToolUse", nested(permissionDecision="deny"), "error"),
    ("wrong event", "PreToolUse", nested(hookEventName="PostToolUse", additionalContext="x"), "error"),
    ("bad context", "PostToolUse", nested(additionalContext=[]), "error"),
    ("bad rewrite", "PreToolUse", nested(updatedInput=None), "error"),
    ("post rewrite", "PostToolUse", nested(updatedInput={}), "error"),
    ("bad continue", "Stop", '{"continue":0}', "error"),
    ("unknown top decision", "Stop", '{"decision":"ask"}', "error"),
]


class Contracts(unittest.TestCase):
    def test_guide_reminders_use_deliverable_fields(self):
        guide = (HERE.parents[1] / "guides" / "hooks-guide.md").read_text()
        for title, event, payload, field in (
            ("3. Self-Check Reminders", "Stop", {}, "systemMessage"),
            ("4. Skill Auto-Activation", "UserPromptSubmit", {"prompt": "deploy the service"}, "hookSpecificOutput"),
        ):
            section = guide.split("### " + title, 1)[1].split("### ", 1)[0]
            script = re.search(r"```bash\n(.*?)```", section, re.S).group(1)
            run = subprocess.run(["bash", "-c", script], input=json.dumps(payload),
                                 text=True, capture_output=True, timeout=5)
            self.assertEqual(0, run.returncode)
            output = json.loads(run.stdout)
            self.assertIn(field, output)
            if event == "UserPromptSubmit":
                self.assertEqual(event, output[field]["hookEventName"])
                self.assertIn("/deploy", output[field]["additionalContext"])
                quiet = subprocess.run(["bash", "-c", script], input='{"prompt":"explain tests"}',
                                       text=True, capture_output=True, timeout=5)
                self.assertEqual((0, ""), (quiet.returncode, quiet.stdout))

    def test_outcomes_and_probe_rejection(self):
        for name, event, stdout, want in CASES:
            with self.subTest(name=name):
                self.assertEqual(want, RUNNER.classify(0, stdout, "", event))
                self.assertEqual(want == "error", bool(PROBE.invariants(event, 0, stdout, "")))
                if want == "error":
                    self.assertIn(PROBE.classify(0, stdout, "", event), ("invalid", "stdout-raw"))

    def test_exit_and_stream_contract(self):
        for event in ("PreToolUse", "PostToolUse", "Stop"):
            self.assertEqual("hard", RUNNER.classify(2, "not JSON", "visible reason", event))
            self.assertEqual("soft", RUNNER.classify(1, "", "error reason", event))
            self.assertEqual("error", RUNNER.classify(0, "", "discarded advice", event))
            self.assertTrue(PROBE.invariants(event, 2, "", ""))
            self.assertFalse(PROBE.invariants(event, 2, "", "visible reason"))

    def test_fixture_event_reaches_classifier(self):
        self.assertEqual("deny", PROBE.classify(0, '{"decision":"block"}', "", "PreToolUse"))
        self.assertEqual("block", PROBE.classify(0, '{"decision":"block"}', "", "Stop"))
        self.assertEqual("allow", PROBE.classify(0, '{"decision":"approve"}', "", "PreToolUse"))
        with tempfile.TemporaryDirectory(prefix="hook-contract-", dir="/tmp") as tmp:
            path = Path(tmp) / "fake.sh"
            path.write_text('cat >/dev/null\nprintf \'{"decision":"block"}\\n\'\n')
            args = type("Args", (), {"timeout": 5})()
            for event, want in (("PreToolUse", "deny"), ("Stop", "block")):
                got = RUNNER.run_case(0, (want, "x", "", "", "Bash", event),
                                      tmp, dict(os.environ), args, path, tmp)
                self.assertEqual(want, got[1])

    def test_nonzero_exit_with_invalid_shape_does_not_crash_probe(self):
        for status in (1, 2):
            for value in (None, 1, [], "invalid"):
                with self.subTest(status=status, value=value):
                    stdout = json.dumps({"hookSpecificOutput": value})
                    self.assertEqual("invalid", PROBE.classify(status, stdout, ""))
                    self.assertTrue(PROBE.invariants("PreToolUse", status, stdout, ""))

    def test_empty_probe_run_fails(self):
        with tempfile.TemporaryDirectory(prefix="probe-empty-", dir="/tmp") as tmp:
            for options in (("--hooks-dir", tmp), ("--only", "no matching probe case")):
                proc = subprocess.run(["python3", str(HERE / "probe-hooks.py"), *options],
                                      capture_output=True, text=True, timeout=10)
                self.assertEqual(1, proc.returncode)
                self.assertIn("no hooks executed", proc.stdout)

    def test_rewrite_cannot_hide_invalid_output(self):
        self.assertEqual("=git status", RUNNER.rewritten(0, nested(updatedInput={"command":"git status"})))
        self.assertEqual("error", RUNNER.rewritten(0, nested(permissionDecision="block", updatedInput={"command":"x"})))
        self.assertEqual("error", RUNNER.rewritten(0, "[]"))
        self.assertEqual("error", RUNNER.rewritten(0, nested(updatedInput={"command":[]})))
        self.assertEqual("invalid", PROBE.classify(2, '{"hookSpecificOutput":null}', ""))

    def test_contract_controls_detect_regressions(self):
        source = (HERE / "run-fixtures.py").read_text()
        changes = [
            ('if "hookSpecificOutput" in parsed and not isinstance(out.get("hookEventName"), str):',
             'if False:'),
            ('PERMISSION_DECISIONS = ("allow", "ask", "deny", "defer")',
             'PERMISSION_DECISIONS = ("allow", "ask", "deny", "defer", "block")'),
            ('except ValueError:\n        return "error"', 'except ValueError:\n        return "allow"'),
            ('if not isinstance(parsed, dict):\n        return "error"',
             'if not isinstance(parsed, dict):\n        return "allow"'),
            ('if "hookSpecificOutput" in parsed and not isinstance(parsed["hookSpecificOutput"], dict):\n        return "error"',
             'if "hookSpecificOutput" in parsed and not isinstance(parsed["hookSpecificOutput"], dict):\n        return "allow"'),
        ]
        for before, after in changes:
            self.assertIn(before, source)
            namespace = {"__name__": "contract_mutant", "__file__": str(HERE / "run-fixtures.py")}
            exec(compile(source.replace(before, after), namespace["__file__"], "exec"), namespace)
            self.assertTrue(any(namespace["classify"](0, out, "", event) != want
                                for _, event, out, want in CASES))


if __name__ == "__main__":
    unittest.main()
