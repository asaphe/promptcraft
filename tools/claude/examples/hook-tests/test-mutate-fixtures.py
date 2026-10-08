#!/usr/bin/env python3
"""Check mutate-fixtures.py scores a mutation only on evidence: a timeout is not a catch.

A run whose every failure is a TIMEOUT says the host was slow, not that the suite noticed the
break, so scoring it as caught turns a loaded CI runner into a green mutation step. Each case
here runs the real scorer against a one-entry manifest, so a regression shows as a wrong exit.
"""

import json
import os
import pathlib
import subprocess
import sys
import tempfile
import unittest

HERE = pathlib.Path(__file__).resolve().parent
HOOKS = HERE.parent / "hooks"
SCORER = HERE / "mutate-fixtures.py"
RUNNER = HERE / "run-fixtures.py"
COMMENT = "# Per-turn grants"
NO_OP = {"why": "a comment-only change, which no fixture can see",
         "replace": {"from": COMMENT, "to": "# Per turn grants"}}


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
        proc = self.score([NO_OP], "--timeout", "0.05")
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


if __name__ == "__main__":
    unittest.main()
