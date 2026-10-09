#!/usr/bin/env python3

import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch


SCRIPT = Path(__file__).with_name("check-adoption.py")
spec = importlib.util.spec_from_file_location("adoption", SCRIPT)
adoption = importlib.util.module_from_spec(spec)
spec.loader.exec_module(adoption)


class AdoptionTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="adoption selftest ")
        self.addCleanup(self.temporary.cleanup)
        self.repo = Path(self.temporary.name) / "repo with spaces"
        self.repo.mkdir()
        paths = {"ADOPTION.md", ".claude/evals/adoption-manifest.json"}
        manifest = json.loads((adoption.ROOT / ".claude/evals/adoption-manifest.json").read_text())
        for recipe in manifest["recipes"]:
            paths.update(artifact["source"] for artifact in recipe["artifacts"])
            paths.update(link["target"] for link in recipe["upstream_links"])
        for relative in sorted(paths):
            source = adoption.ROOT / relative
            destination = self.repo / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            if source.is_dir():
                shutil.copytree(source, destination)
            else:
                shutil.copy2(source, destination)
        subprocess.run(["git", "init", "-q"], cwd=self.repo, check=True, capture_output=True)
        subprocess.run(["git", "add", "."], cwd=self.repo, check=True, capture_output=True)

    def mutate_snippet(self, name, transform):
        path = self.repo / "ADOPTION.md"
        text = path.read_text()
        block = adoption.snippets(self.repo)[name]
        path.write_text(text.replace(block, transform(block), 1))

    def mutate_manifest(self, transform):
        path = self.repo / ".claude/evals/adoption-manifest.json"
        manifest = json.loads(path.read_text())
        transform(manifest)
        path.write_text(json.dumps(manifest))

    def assert_rejected(self, message):
        with self.assertRaisesRegex(ValueError, message):
            adoption.check(self.repo, collision=False)

    def test_positive_exact_snippets_spaces_and_all_collisions(self):
        self.assertEqual(adoption.check(self.repo), 4)

    def test_missing_parent(self):
        self.mutate_snippet("basic", lambda b: b.replace('mkdir -p "$HOME/.claude"', ":"))
        self.assert_rejected("recipe failed: basic")

    def test_each_missing_bundle_member(self):
        original = (self.repo / "ADOPTION.md").read_text()
        for name in adoption.HOOKS:
            with self.subTest(name=name):
                (self.repo / "ADOPTION.md").write_text(original)
                self.mutate_snippet("hooks", lambda b: "\n".join(line for line in b.splitlines()
                                    if not line.startswith(f"cp -R tools/claude/examples/hooks/{name} ")))
                self.assert_rejected("missing or unsupported artifact")

    def test_each_missing_installed_helper(self):
        original = (self.repo / "ADOPTION.md").read_text()
        for helper in adoption.HELPERS:
            with self.subTest(helper=helper):
                (self.repo / "ADOPTION.md").write_text(original)
                self.mutate_snippet("hooks", lambda b: b + f'\nrm "$HOME/.claude/hooks/_lib/{helper}"')
                self.assert_rejected("bytes/layout differ")

    def test_missing_source_helper(self):
        (self.repo / "tools/claude/examples/hooks/_lib/strip-quoted-args.pl").unlink()
        self.assert_rejected("missing runtime dependency")

    def test_extra_hook_directory(self):
        self.mutate_snippet("hooks", lambda b: b + '\nmkdir "$HOME/.claude/hooks/extra-hook"')
        self.assert_rejected("extra installed artifact")

    def test_bulk_hook_copy(self):
        extra = self.repo / "tools/claude/examples/hooks/extra-hook"
        extra.mkdir(); (extra / "extra.sh").write_text("exit 0\n")
        self.mutate_snippet("hooks", lambda b: b + '\ncp -R tools/claude/examples/hooks/extra-hook "$HOME/.claude/hooks/"')
        self.assert_rejected("extra installed artifact")

    def test_manifest_paths_cannot_escape(self):
        original = (self.repo / ".claude/evals/adoption-manifest.json").read_text()
        for field in ("source", "destination", "runtime_dependencies"):
            for value in ("../outside", "/tmp/outside", "a/../../outside"):
                with self.subTest(field=field, value=value):
                    (self.repo / ".claude/evals/adoption-manifest.json").write_text(original)
                    def mutate(manifest):
                        recipe = manifest["recipes"][0]
                        if field == "runtime_dependencies":
                            recipe[field] = [value]
                        else:
                            recipe["artifacts"][0][field] = value
                    self.mutate_manifest(mutate)
                    self.assert_rejected("invalid relative path")

    def test_resolved_source_escape(self):
        path = self.repo / "tools/claude/examples/config/global-CLAUDE.md"
        path.unlink()
        outside = Path(self.temporary.name) / "outside.md"
        outside.write_text("outside\n")
        path.symlink_to(outside)
        self.assert_rejected("path escapes root")

    def test_missing_dependency_declaration(self):
        self.mutate_manifest(lambda m: m["recipes"][2]["runtime_dependencies"].pop())
        self.assert_rejected("dependency declarations")

    def test_new_source_helper_requires_dependency_declaration(self):
        (self.repo / "tools/claude/examples/hooks/_lib/new-helper.sh").write_text("exit 0\n")
        self.assert_rejected("dependency declarations")

    def test_extra_hook_artifact_declaration(self):
        self.mutate_manifest(lambda m: m["recipes"][2]["artifacts"].pop())
        self.assert_rejected("unexpected artifact bundle")

    def test_relocated_broken_link(self):
        path = self.repo / "tools/claude/scaffolding/.claude/CLAUDE.md"
        path.write_text(path.read_text() + "\n[Missing](docs/missing.md)\n")
        self.assert_rejected("broken or escaping relocated link")

    def test_relocated_escape_link(self):
        path = self.repo / "tools/claude/scaffolding/.claude/CLAUDE.md"
        path.write_text(path.read_text() + "\n[Escape](../../ADOPTION.md)\n")
        self.assert_rejected("broken or escaping relocated link")

    def test_relocated_reference_link(self):
        path = self.repo / "tools/claude/scaffolding/.claude/CLAUDE.md"
        path.write_text(path.read_text() + "\n[Missing][help]\n\n[help]: docs/missing.md\n")
        self.assert_rejected("broken or escaping relocated link")

    def test_relocated_link_with_spaces(self):
        path = self.repo / "tools/claude/scaffolding/.claude/CLAUDE.md"
        document = path.parent / "docs/file with spaces.md"
        document.write_text("# Local help\n")
        path.write_text(path.read_text() + "\n[Help](<docs/file with spaces.md>)\n")
        self.mutate_manifest(lambda m: m["recipes"][3]["runtime_dependencies"].append(".claude/docs/file with spaces.md"))
        self.assertEqual(adoption.check(self.repo, collision=False), 4)

    def test_hooks_relocated_broken_link(self):
        path = self.repo / "tools/claude/examples/hooks/destructive-guard/README.md"
        path.write_text(path.read_text() + "\n[Missing](../uninstalled-hook/README.md)\n")
        self.assert_rejected("broken or escaping relocated link")

    def test_upstream_target_missing(self):
        (self.repo / "tools/claude/templates/agents/agent-template.md").unlink()
        self.assert_rejected("missing upstream target")

    def test_upstream_link_undeclared(self):
        self.mutate_manifest(lambda m: m["recipes"][3]["upstream_links"].pop())
        self.assert_rejected("undeclared upstream link")

    def test_collision_guard_removed(self):
        self.mutate_snippet("basic", lambda b: b.replace('  exit 1', '  :'))
        self.assert_rejected("second run modified destination or accepted collision")

    def test_missing_delimiter(self):
        path = self.repo / "ADOPTION.md"
        path.write_text(path.read_text().replace("<!-- adoption:basic -->", ""))
        self.assert_rejected("four delimited")

    def test_required_tools_checked_without_cloud_invocation(self):
        original = adoption.shutil.which
        for tool in ("bash", "jq", "perl", "git", "cp", "mkdir"):
            with self.subTest(tool=tool), patch.object(adoption.shutil, "which", side_effect=lambda name: None if name == tool else original(name)):
                self.assert_rejected(f"missing adoption dependency on PATH: {tool}")


if __name__ == "__main__":
    unittest.main(verbosity=2)
