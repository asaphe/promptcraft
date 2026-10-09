#!/usr/bin/env python3
"""Check mutate-fixtures.py scores a mutation only on evidence: a timeout is not a catch.

A run whose every failure is a TIMEOUT says the host was slow, not that the suite noticed the
break, so scoring it as caught turns a loaded CI runner into a green mutation step. Each case
here runs the real scorer against a one-entry manifest, so a regression shows as a wrong exit.
"""

import collections
import importlib.util
import json
import os
import pathlib
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
import unittest

HERE = pathlib.Path(__file__).resolve().parent
HOOKS = HERE.parent / "hooks"
SCORER = HERE / "mutate-fixtures.py"
RUNNER = HERE / "run-fixtures.py"
WORKFLOW = HERE.parents[3] / ".github" / "workflows" / "hook-evals.yml"
COMMENT = "# Per-turn grants"
NO_OP = {"why": "a comment-only change, which no fixture can see",
         "replace": {"from": COMMENT, "to": "# Per turn grants"}}
# Sleeps past any --timeout below, so every case times out however fast the runner is.
SLOW = {"why": "a hook that sleeps past the per-case timeout",
        "replace": {"from": COMMENT, "to": "sleep 5\n# Per turn grants"}}


def real_mutation(index=0):
    return json.loads((HERE / "mutations.json").read_text())["merge-grant"][index]


class MutateFixturesTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="mutate-test-")

    def score(self, entries, *extra):
        manifest = pathlib.Path(self.tmp) / "manifest.json"
        manifest.write_text(json.dumps({"merge-grant": entries}))
        return subprocess.run(
            [sys.executable, str(SCORER), "--hooks-dir", str(HOOKS), "--manifest", str(manifest),
             *extra, "merge-grant"],
            capture_output=True, text=True, timeout=600)

    def test_a_run_that_only_timed_out_is_inconclusive_and_fails(self):
        self.assertIn(COMMENT, (HOOKS / "merge-grant" / "merge-grant.sh").read_text())
        proc = self.score([SLOW], "--timeout", "0.2")
        self.assertEqual(proc.returncode, 1, proc.stdout)
        self.assertIn("INCONCLUSIVE", proc.stdout)
        self.assertIn("0/1 mutations caught", proc.stdout)

    def test_a_mutation_the_suite_misses_fails(self):
        proc = self.score([NO_OP], "--timeout", "60")
        self.assertEqual(proc.returncode, 1, proc.stdout)
        self.assertIn("suite still passed", proc.stdout)
        self.assertNotIn("INCONCLUSIVE", proc.stdout)

    def test_a_mutation_the_suite_catches_passes(self):
        proc = self.score([real_mutation()], "--timeout", "60")
        self.assertEqual(proc.returncode, 0, proc.stdout)
        self.assertIn("1/1 mutations caught", proc.stdout)

    def test_shards_split_the_mutations_without_overlap(self):
        inert = [{"why": "inert-%d" % i, "replace": {"from": "no such text %d" % i, "to": "x"}}
                 for i in range(3)]
        seen = []
        for shard in ("1/2", "2/2"):
            proc = self.score(inert, "--shard", shard)
            seen += [e["why"] for e in inert if e["why"] in proc.stdout]
        self.assertEqual(sorted(seen), ["inert-0", "inert-1", "inert-2"])

    def test_fail_fast_stops_at_the_first_real_failure(self):
        broken = pathlib.Path(self.tmp) / "hooks"
        subprocess.run(["cp", "-R", str(HOOKS), str(broken)], check=True)
        hook = broken / "merge-grant" / "merge-grant.sh"
        hook.write_text("#!/usr/bin/env bash\nexit 0\n")
        proc = subprocess.run(
            [sys.executable, str(RUNNER), "merge-grant", "--hooks-dir", str(broken), "--fail-fast"],
            capture_output=True, text=True, timeout=600, env=dict(os.environ))
        self.assertEqual(proc.returncode, 1, proc.stdout)
        fails = [ln for ln in proc.stdout.splitlines() if ln.startswith("FAIL")]
        self.assertEqual(len(fails), 1, proc.stdout)
        self.assertIn("stopped at the first failure", proc.stdout)


    def test_fail_fast_with_jobs_still_stops_at_the_first_real_failure(self):
        broken = pathlib.Path(self.tmp) / "hooks"
        subprocess.run(["cp", "-R", str(HOOKS), str(broken)], check=True)
        (broken / "merge-grant" / "merge-grant.sh").write_text("#!/usr/bin/env bash\nexit 0\n")
        proc = subprocess.run(
            [sys.executable, str(RUNNER), "merge-grant", "--hooks-dir", str(broken), "--fail-fast", "--jobs", "4"],
            capture_output=True, text=True, timeout=600, env=dict(os.environ))
        self.assertEqual(proc.returncode, 1, proc.stdout)
        fails = [ln for ln in proc.stdout.splitlines() if ln.startswith("FAIL")]
        self.assertEqual(len(fails), 1, proc.stdout)
        self.assertIn("stopped at the first failure", proc.stdout)

    def test_jobs_print_the_same_cases_in_the_same_order(self):
        runs = [subprocess.run([sys.executable, str(RUNNER), "merge-grant", "--hooks-dir", str(HOOKS), *extra],
                               capture_output=True, text=True, timeout=600)
                for extra in ((), ("--jobs", "4"))]
        self.assertEqual(runs[0].returncode, 0, runs[0].stdout[-500:])
        self.assertEqual(runs[0].stdout, runs[1].stdout)

    def test_jobs_below_one_is_refused(self):
        proc = subprocess.run([sys.executable, str(RUNNER), "merge-grant", "--hooks-dir", str(HOOKS), "--jobs", "0"],
                              capture_output=True, text=True, timeout=60)
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("--jobs must be 1 or more", proc.stderr)

    def test_a_run_that_crashes_is_inconclusive(self):
        proc = self.score([dict(NO_OP, suite="no-such-suite")], "--timeout", "60")
        self.assertEqual(proc.returncode, 1, proc.stdout)
        self.assertIn("INCONCLUSIVE", proc.stdout)
        self.assertIn("0/1 mutations caught", proc.stdout)

    def test_fail_fast_runs_past_timeouts(self):
        spec = importlib.util.spec_from_file_location("run_fixtures", RUNNER)
        runner = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(runner)
        cases, _ = runner.parse_fixture(HERE / "fixtures" / "merge-grant.tsv")
        proc = subprocess.run(
            [sys.executable, str(RUNNER), "merge-grant", "--hooks-dir", str(HOOKS), "--fail-fast",
             "--timeout", "0.01"], capture_output=True, text=True, timeout=600)
        self.assertNotIn("stopped at the first failure", proc.stdout)
        ran = re.search(r"^(\d+)/(\d+) passed$", proc.stdout, re.M)
        self.assertIsNotNone(ran, proc.stdout[-500:])
        self.assertEqual(int(ran.group(2)), len(cases))

    def test_a_caught_rewrite_mutation_is_scored_caught(self):
        tree = pathlib.Path(self.tmp) / "tree"
        shutil.copytree(HERE, tree / "hook-tests")
        hook = tree / "hooks" / "toy-rewrite" / "toy-rewrite.sh"
        hook.parent.mkdir(parents=True)
        # A rewritten command holds a space, which a space-delimited summary row cannot carry.
        hook.write_text('#!/usr/bin/env bash\ncmd=$(jq -r .tool_input.command)\n'
                        'jq -nc --arg c "wrap $cmd" \'{hookSpecificOutput: {hookEventName: "PreToolUse",'
                        ' updatedInput: {command: $c}}}\'\n')
        (tree / "hook-tests" / "fixtures" / "toy-rewrite.tsv").write_text("=wrap git status\tgit status\n")
        manifest = pathlib.Path(self.tmp) / "toy.json"
        manifest.write_text(json.dumps({"toy-rewrite": [
            {"why": "the rewrite prefix changes", "replace": {"from": "wrap $cmd", "to": "other $cmd"}}]}))
        proc = subprocess.run(
            [sys.executable, str(tree / "hook-tests" / "mutate-fixtures.py"), "--hooks-dir", str(tree / "hooks"),
             "--manifest", str(manifest), "--timeout", "60", "toy-rewrite"],
            capture_output=True, text=True, timeout=600)
        self.assertEqual(proc.returncode, 0, proc.stdout)
        self.assertIn("1/1 mutations caught", proc.stdout)

    @unittest.skipUnless(WORKFLOW.is_file(), "the CI workflow is not beside this copy of the tests")
    def test_ci_runs_every_manifest_entry_exactly_once(self):
        lines = re.findall(r"^\s*args:\s*(.+?)\s*$", WORKFLOW.read_text(), re.M)
        self.assertTrue(lines)
        real = {k: v for k, v in json.loads((HERE / "mutations.json").read_text()).items() if k != "_README"}
        # Inert entries fail at once, so the scorer names each one without running a suite.
        inert = {k: [dict({"suite": e["suite"]} if "suite" in e else {}, why="%s#%d" % (k, i),
                          replace={"from": "\x00 no such text", "to": "x"}) for i, e in enumerate(v)]
                 for k, v in real.items()}
        manifest = pathlib.Path(self.tmp) / "inert.json"
        manifest.write_text(json.dumps(inert))
        seen = collections.Counter()
        for line in lines:
            proc = subprocess.run([sys.executable, str(SCORER), "--hooks-dir", str(HOOKS),
                                   "--manifest", str(manifest), *shlex.split(line)],
                                  capture_output=True, text=True, timeout=600)
            seen.update(re.findall(r"INERT MUTATION \u2014 (\S+#\d+)$", proc.stdout, re.M))
        want = collections.Counter("%s#%d" % (k, i) for k, v in real.items() for i in range(len(v)))
        self.assertEqual(seen, want)


if __name__ == "__main__":
    unittest.main()
