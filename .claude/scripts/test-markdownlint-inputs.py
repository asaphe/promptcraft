#!/usr/bin/env python3

import importlib.util
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).with_name("markdownlint-inputs.py")
spec = importlib.util.spec_from_file_location("markdown_inputs", SCRIPT)
inputs = importlib.util.module_from_spec(spec)
spec.loader.exec_module(inputs)


class MarkdownInputTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="lint input selftest ")
        self.addCleanup(temporary.cleanup)
        self.repo = Path(temporary.name) / "repo with spaces"
        self.repo.mkdir()
        subprocess.run(["git", "init", "-q"], cwd=self.repo, check=True, capture_output=True)
        (self.repo / ".markdownlintignore").write_text("")

    def track(self, *paths):
        for relative in paths:
            path = self.repo / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("# Example\n")
        subprocess.run(["git", "add", "--", *paths], cwd=self.repo, check=True, capture_output=True)

    def ignore(self, text):
        (self.repo / ".markdownlintignore").write_text(text)

    def test_tracked_hidden_spaces_and_both_extensions(self):
        self.track("README.md", ".claude/hidden.md", "space dir/a.markdown", "not.txt", "UPPER.MD")
        (self.repo / "untracked.md").write_text("# Untracked\n")
        self.assertEqual(inputs.lint_inputs(self.repo),
                         ":.claude/hidden.md\n:README.md\n:space dir/a.markdown\n")

    def test_nine_exact_exclusions(self):
        ignored = [f"hidden dir/excluded-{index}.md" for index in range(9)]
        self.track("keep.md", *ignored)
        self.ignore("# Existing exclusions\n\n" + "\n".join(ignored) + "\n")
        self.assertEqual(inputs.lint_inputs(self.repo), ":keep.md\n")

    def test_empty_untracked_only_and_fully_excluded(self):
        for tracked in (False, True):
            with self.subTest(tracked=tracked):
                if tracked:
                    self.track("only.md"); self.ignore("only.md\n")
                else:
                    (self.repo / "untracked.md").write_text("# Untracked\n")
                with self.assertRaisesRegex(ValueError, "empty tracked Markdown corpus"):
                    inputs.lint_inputs(self.repo)

    def test_unsupported_ignore_patterns_and_escapes(self):
        self.track("keep.md")
        for entry in ("*.md", "!keep.md", "[ab].md", "a?.md", "{a,b}.md", "a\\b.md",
                      "../keep.md", "/keep.md", "a/../../keep.md", "./keep.md"):
            with self.subTest(entry=entry):
                self.ignore(entry + "\n")
                with self.assertRaises(ValueError):
                    inputs.lint_inputs(self.repo)

    def test_missing_untracked_non_markdown_and_duplicate_exclusions(self):
        self.track("keep.md", "file.txt")
        (self.repo / "untracked.md").write_text("# Untracked\n")
        for text in ("missing.md\n", "untracked.md\n", "file.txt\n", "keep.md\nkeep.md\n",
                     "keep.md\nother.md\n"):
            with self.subTest(text=text):
                self.ignore(text)
                with self.assertRaisesRegex(ValueError, "one tracked Markdown file"):
                    inputs.lint_inputs(self.repo)

    def test_newline_and_carriage_return_paths(self):
        for path in ("line\nbreak.md", "line\rbreak.md"):
            with self.subTest(path=path):
                self.track(path)
                with self.assertRaisesRegex(ValueError, "unsupported Markdown path"):
                    inputs.lint_inputs(self.repo)

    def test_literal_metacharacters_not_shell_expansion(self):
        self.track("bracket[1].md", "star*.md", "cash$().md", "!leading.md")
        self.assertEqual(inputs.lint_inputs(self.repo),
                         ":!leading.md\n:bracket[1].md\n:cash$().md\n:star*.md\n")

    def test_cli_multiline_step_output_matches_stdout(self):
        self.track(".claude/hidden.md", "space dir/a.md")
        output_file = self.repo / "step output"
        result = subprocess.run(["python3", str(SCRIPT), "--repo", str(self.repo),
                                 "--github-output", str(output_file)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        lines = output_file.read_text().splitlines()
        self.assertTrue(lines[0].startswith("globs<<markdownlint_"))
        self.assertEqual(lines[0].split("<<", 1)[1], lines[-1])
        self.assertEqual("\n".join(lines[1:-1]) + "\n", result.stdout)

    def test_cli_failure_does_not_write_partial_output(self):
        output_file = self.repo / "step output"
        result = subprocess.run(["python3", str(SCRIPT), "--repo", str(self.repo),
                                 "--github-output", str(output_file)], capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")
        self.assertFalse(output_file.exists())

    def test_alternate_index_includes_new_files_without_staging_real_index(self):
        self.track("tracked.md")
        (self.repo / "new.md").write_text("# New\n")
        real_index = (self.repo / ".git/index").read_bytes()
        alternate = self.repo / "alternate index"
        alternate.write_bytes(real_index)
        environment = dict(os.environ, GIT_INDEX_FILE=str(alternate))
        subprocess.run(["git", "add", "--", "new.md"], cwd=self.repo, env=environment,
                       check=True, capture_output=True)
        result = subprocess.run(["python3", str(SCRIPT), "--repo", str(self.repo)],
                                env=environment, check=True, text=True, capture_output=True)
        self.assertEqual(result.stdout, ":new.md\n:tracked.md\n")
        self.assertEqual((self.repo / ".git/index").read_bytes(), real_index)


if __name__ == "__main__":
    unittest.main(verbosity=2)
