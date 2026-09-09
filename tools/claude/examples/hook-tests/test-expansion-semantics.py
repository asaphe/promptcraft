#!/usr/bin/env python3
"""Check Bash expansion semantics and the destructive-guard verdict together."""

import importlib.util
import json
import os
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile
import unittest


HERE = pathlib.Path(__file__).resolve().parent
FIXTURES = HERE / "fixtures" / "destructive-guard.tsv"
HOOK = HERE.parent / "hooks" / "destructive-guard" / "destructive-guard.sh"
ABSOLUTE_EXECUTABLE = re.compile(r"(?:^|[\s;|&()'\"])/[^\s;|&()'\"]+")
DESTRUCTIVE_FILESYSTEM = re.compile(
    r"\b(?:rm\s+(?:-[A-Za-z]*[rf]|--(?:force|recursive))|rmdir\s|unlink\s|find\b[^\n]*\s-delete)"
)
ORACLE_ESCAPE = re.compile(
    r"(?:^|[\s;|&])(?:PATH|BASH_ENV|ENV|ORACLE_BASH|ORACLE_PYTHON|TRACE_FILE)=[^\s;|&]*"
    r"|(?:^|[\s;|&])command[ \t]+-p(?:[ \t]|$)"
)


def load_runner():
    spec = importlib.util.spec_from_file_location("run_fixtures", HERE / "run-fixtures.py")
    module = importlib.util.module_from_spec(spec)
    assert spec and spec.loader
    spec.loader.exec_module(module)
    return module


RUNNER = load_runner()


def oracle_cases():
    cases = []
    pending = None
    escaped = False
    for raw in FIXTURES.read_text(encoding="utf-8").splitlines():
        if raw == "#!escapes":
            escaped = True
            continue
        if raw.startswith("#!oracle\t"):
            if pending is not None:
                raise AssertionError("consecutive oracle directives: %s then %s" % (pending[0], raw))
            fields = raw.split("\t")
            if len(fields) not in (3, 4, 5):
                raise AssertionError("malformed oracle directive: %s" % raw)
            pending = (fields[1], "" if fields[2] == "-" else fields[2], fields[3] if len(fields) >= 4 else "",
                       fields[4] if len(fields) == 5 else "")
            continue
        if raw.startswith("#") or not raw.strip():
            continue
        expected, separator, command = raw.partition("\t")
        if pending is None:
            continue
        if not separator:
            raise AssertionError("oracle directive has no fixture: %s" % pending[0])
        if escaped:
            command = RUNNER.unescape_cmd(command)
        if ORACLE_ESCAPE.search(command):
            raise AssertionError("oracle fixture escapes its hermetic environment: %s" % pending[0])
        cases.append((pending[0], expected, command, pending[1], pending[2], pending[3]))
        pending = None
    if pending is not None:
        raise AssertionError("oracle directive has no fixture: %s" % pending[0])
    return cases


class ExpansionSemanticsTest(unittest.TestCase):
    def test_fixture_tripwires(self):
        corpus = FIXTURES.read_text(encoding="utf-8")
        self.assertIsNone(ABSOLUTE_EXECUTABLE.search(corpus))
        self.assertIsNone(DESTRUCTIVE_FILESYSTEM.search(corpus))

    def test_absolute_path_tripwire(self):
        self.assertIsNotNone(ABSOLUTE_EXECUTABLE.search("/usr/local/bin/tool"))
        self.assertIsNotNone(ABSOLUTE_EXECUTABLE.search("/opt/homebrew/bin/tool"))
        self.assertIsNone(ABSOLUTE_EXECUTABLE.search("cd /"))

    def test_oracle_fixtures_keep_probe_env_hermetic(self):
        cases = oracle_cases()
        self.assertTrue(cases)
        for name, _, command, *_ in cases:
            self.assertIsNone(ABSOLUTE_EXECUTABLE.search(command), name)
            self.assertIsNone(DESTRUCTIVE_FILESYSTEM.search(command), name)

    def test_bash_expansion_and_guard_agree(self):
        bash_paths = [pathlib.Path("/bin/bash"), pathlib.Path("/opt/homebrew/bin/bash")]
        for bash in bash_paths:
            if not bash.is_file():
                continue
            with self.subTest(bash=str(bash)):
                self.run_bash_oracle(bash)

    def test_quote_parser_failures_fail_closed(self):
        command = next(command for name, _, command, *_ in oracle_cases()
                       if name == "helper-failure-control")
        with tempfile.TemporaryDirectory(prefix="quote-parser-failure-") as raw_tmp:
            tmp = pathlib.Path(raw_tmp)
            startup = tmp / "startup"
            startup.write_text("", encoding="utf-8")
            for kind in ("missing", "invalid"):
                with self.subTest(kind=kind):
                    tree = tmp / kind / "hooks"
                    shutil.copytree(HERE.parent / "hooks", tree)
                    helper = tree / "_lib" / "strip-quoted-args.pl"
                    if kind == "missing":
                        helper.unlink()
                    else:
                        helper.write_text('die "fixture parser failure\\n";\n', encoding="utf-8")
                    verdict = subprocess.run(
                        ["/bin/bash", str(tree / "destructive-guard" / "destructive-guard.sh")],
                        input=json.dumps({"tool_input": {"command": command}}),
                        cwd=tmp,
                        env=self.guard_env(tmp, startup),
                        capture_output=True,
                        text=True,
                        check=False,
                        timeout=10,
                    )
                    self.assertEqual(2, verdict.returncode)
                    self.assertIn("command preprocessing failed", verdict.stderr)

    def run_bash_oracle(self, bash):
        with tempfile.TemporaryDirectory(prefix="expansion-oracle-") as raw_tmp:
            tmp = pathlib.Path(raw_tmp)
            stubs = tmp / "stubs"
            stubs.mkdir()
            trace = tmp / "trace"
            startup = tmp / "startup"
            startup.write_text("", encoding="utf-8")
            self.install_stubs(stubs)
            env = {
                "BASH_ENV": str(startup),
                "ENV": str(startup),
                "HOME": str(tmp / "home"),
                "PATH": str(stubs),
                "TRACE_FILE": str(trace),
                "ORACLE_BASH": str(bash),
                "ORACLE_PYTHON": str(pathlib.Path(sys.executable).resolve()),
            }
            for name, expected, command, wanted_trace, setup, oracle_expected in oracle_cases():
                working = self.setup_repositories(tmp, setup)
                script = tmp / (name + ".sh")
                script.write_text(command + "\n", encoding="utf-8")
                trace.write_text("", encoding="utf-8")
                observed = subprocess.run(
                    [str(bash), "--noprofile", "--norc", str(script)],
                    cwd=working,
                    env=env,
                    capture_output=True,
                    text=True,
                    check=False,
                    timeout=10,
                )
                self.assertEqual(0, observed.returncode, "%s: %s" % (name, observed.stderr))
                actual_trace = "|".join(trace.read_text(encoding="utf-8").splitlines())
                self.assertEqual(wanted_trace, actual_trace, name)
                verdict = subprocess.run(
                    [str(bash), str(HOOK)],
                    input=json.dumps({"tool_input": {"command": command}}),
                    cwd=working,
                    env=self.guard_env(tmp, startup),
                    capture_output=True,
                    text=True,
                    check=False,
                    timeout=10,
                )
                self.assertEqual(oracle_expected or expected,
                                 RUNNER.classify(verdict.returncode, verdict.stdout, verdict.stderr), name)

    @staticmethod
    def guard_env(tmp, startup):
        return dict(
            os.environ,
            BASH_ENV=str(startup),
            ENV=str(startup),
            HOOK_DIAG_LOG=str(tmp / "blocks.log"),
            HOOK_DIAG_ALLOW_LOG=str(tmp / "allows.log"),
            HOOK_DIAG_ASK_LOG=str(tmp / "asks.log"),
            CLAUDE_HOOK_FIXTURE_RUN="1",
        )

    @staticmethod
    def setup_repositories(tmp, setup):
        if not setup:
            return tmp
        if setup == "inert-script":
            (tmp / "inert-script").write_text("exit 0\n", encoding="utf-8")
            return tmp
        if setup == "inert-python-script":
            (tmp / "inert-python-script").write_text("pass\n", encoding="utf-8")
            return tmp
        if setup != "target-repos":
            raise AssertionError("unknown oracle setup: %s" % setup)
        target = tmp / "target"
        target.mkdir(exist_ok=True)
        git = shutil.which("git")
        if not git:
            raise AssertionError("git is required to build the temporary repository control")
        git = str(pathlib.Path(git).resolve())
        for repository in (tmp, target):
            subprocess.run([git, "init", "-q", str(repository)], check=True, capture_output=True, timeout=10)
        return tmp

    @staticmethod
    def install_stubs(stubs):
        stub = """#!/bin/sh
name=${0##*/}
printf '%s:' "$name" >> "$TRACE_FILE"
sep=''
for argument in "$@"; do
  printf '%s%s' "$sep" "$argument" >> "$TRACE_FILE"
  sep=,
done
printf '\n' >> "$TRACE_FILE"
printf '0\n'
"""
        for name in ("git", "gh", "aws", "cat", "terraform", "kubectl", "helm"):
            path = stubs / name
            path.write_text(stub, encoding="utf-8")
            path.chmod(0o755)
        bash_stub = stub.replace("printf '0\n'", 'exec "$ORACLE_BASH" "$@"')
        (stubs / "bash").write_text(bash_stub, encoding="utf-8")
        (stubs / "bash").chmod(0o755)
        env_stub = stub.replace("printf '0\n'", 'if [ "$1" = bash ]; then shift; exec bash "$@"; fi')
        (stubs / "env").write_text(env_stub, encoding="utf-8")
        (stubs / "env").chmod(0o755)
        python_stub = stub.replace("printf '0\n'", 'exec "$ORACLE_PYTHON" "$@"')
        for name in ("python", "python3"):
            (stubs / name).write_text(python_stub, encoding="utf-8")
            (stubs / name).chmod(0o755)


if __name__ == "__main__":
    unittest.main()
