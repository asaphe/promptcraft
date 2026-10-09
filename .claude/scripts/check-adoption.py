#!/usr/bin/env python3

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import subprocess
import sys
import tempfile
from urllib.parse import unquote, urlsplit


ROOT = Path(__file__).resolve().parents[2]
PREFIX = "https://github.com/asaphe/promptcraft/blob/main/"
HOOKS = ("destructive-guard", "stateful-op-reminder", "pr-create-guard", "_lib")
HELPERS = ("hook-diag.sh", "pr-author.sh", "resolve-workdir.sh", "strip-cmd.sh",
           "strip-quoted-args.pl", "split-cmd-segments.pl")
SOURCES = {
    "basic": ("home", [("tools/claude/examples/config/global-CLAUDE.md", ".claude/CLAUDE.md", "file")]),
    "operations": ("project", [("tools/claude/examples/profiles/operations.md", ".claude/rules/operations.md", "file")]),
    "hooks": ("home", [(f"tools/claude/examples/hooks/{name}", f".claude/hooks/{name}", "tree") for name in HOOKS]),
    "scaffold": ("project", [("tools/claude/scaffolding/.claude", ".claude", "tree")]),
}


def inside(root, relative):
    path = PurePosixPath(relative)
    if (not relative or path.is_absolute() or ".." in path.parts
            or str(path) != relative or any(c in relative for c in "\n\r\0\\")):
        raise ValueError(f"invalid relative path: {relative!r}")
    resolved = (root / relative).resolve()
    if not resolved.is_relative_to(root.resolve()):
        raise ValueError(f"path escapes root: {relative}")
    return root / relative


def inventory(root):
    entries = {}
    paths = [root] + sorted(root.rglob("*")) if root.is_dir() and not root.is_symlink() else [root]
    for path in paths:
        key = str(path.relative_to(root))
        if path.is_symlink():
            entries[key] = ("link", os.readlink(path))
        elif path.is_file():
            entries[key] = ("file", hashlib.sha256(path.read_bytes()).hexdigest(), path.stat().st_mode & 0o777)
        elif path.is_dir():
            entries[key] = ("directory",)
        else:
            raise ValueError(f"missing or unsupported artifact: {path}")
    return entries


def load_manifest(repo):
    manifest = json.loads((repo / ".claude/evals/adoption-manifest.json").read_text())
    if set(manifest) != {"version", "recipes"} or manifest["version"] != 1:
        raise ValueError("unsupported manifest schema/version")
    recipes = manifest["recipes"]
    if not isinstance(recipes, list) or sorted(r["id"] for r in recipes) != sorted(SOURCES):
        raise ValueError("manifest must declare exactly the four copy-ready routes")
    tracked = set(subprocess.check_output(["git", "ls-files", "-z"], cwd=repo).decode().split("\0"))
    for recipe in recipes:
        if set(recipe) != {"id", "root", "artifacts", "runtime_dependencies", "upstream_links"}:
            raise ValueError("unsupported recipe schema")
        expected_root, expected_artifacts = SOURCES[recipe["id"]]
        actual = []
        for artifact in recipe["artifacts"]:
            if set(artifact) != {"source", "destination", "kind"}:
                raise ValueError("unsupported artifact schema")
            source = inside(repo, artifact["source"])
            inside(repo, artifact["destination"])
            if artifact["kind"] == "file" and not source.is_file():
                raise ValueError(f"missing source file: {source}")
            if artifact["kind"] == "tree" and not source.is_dir():
                raise ValueError(f"missing source tree: {source}")
            if any(value[0] == "link" for value in inventory(source).values()):
                raise ValueError(f"symlinked source artifact: {source}")
            actual.append((artifact["source"], artifact["destination"], artifact["kind"]))
        if recipe["root"] != expected_root or sorted(actual) != sorted(expected_artifacts):
            raise ValueError(f"unexpected artifact bundle: {recipe['id']}")
        dependencies = recipe["runtime_dependencies"]
        if not isinstance(dependencies, list) or len(set(dependencies)) != len(dependencies):
            raise ValueError("runtime dependencies must be unique relative paths")
        for dependency in dependencies:
            inside(repo, dependency)
        if recipe["id"] == "hooks":
            expected = {f".claude/hooks/_lib/{helper}" for helper in HELPERS}
            expected.update(f".claude/hooks/{name}/{name}.sh" for name in HOOKS if name != "_lib")
            for artifact in recipe["artifacts"]:
                source = repo / artifact["source"]
                expected.update(f"{artifact['destination']}/{p.relative_to(source)}"
                                for p in source.rglob("*") if p.suffix in {".sh", ".pl"})
            if set(dependencies) != expected:
                raise ValueError("incomplete or extra hook runtime dependency declarations")
        elif recipe["id"] == "scaffold":
            source = repo / expected_artifacts[0][0]
            expected = {f".claude/{p.relative_to(source)}" for p in source.rglob("*") if p.is_file()}
            if set(dependencies) != expected:
                raise ValueError("scaffold must declare every copied file dependency")
        elif dependencies:
            raise ValueError("standalone routes have no companion dependencies")
        for link in recipe["upstream_links"]:
            if set(link) != {"url", "target"} or link["url"] != PREFIX + link["target"]:
                raise ValueError("upstream link must map a public browsing URL to its source")
            if link["target"] not in tracked or not inside(repo, link["target"]).is_file():
                raise ValueError(f"untracked or missing upstream target: {link['target']}")
    return recipes


def snippets(repo):
    text = (repo / "ADOPTION.md").read_text()
    found = re.findall(
        r"<!-- adoption:([a-z]+) -->\s*```bash\n(.*?)\n```\s*<!-- /adoption:\1 -->",
        text, re.S,
    )
    ids = [name for name, _ in found]
    if sorted(ids) != sorted(SOURCES) or text.count("<!-- adoption:") != 4 or text.count("<!-- /adoption:") != 4:
        raise ValueError("expected exactly four delimited Bash recipes")
    return dict(found)


def markdown_links(text):
    text = re.sub(r"(?m)^```[^\n]*\n.*?^```[^\n]*$", "", text, flags=re.S)
    inline = re.findall(r"\[[^\]]*\]\((<[^>]*>|[^\s)]+)(?:\s+\"[^\"]*\")?\)", text)
    references = re.findall(r"(?m)^ {0,3}\[[^\]]+\]:\s*(<[^>]*>|\S+)", text)
    return inline + references


def check_links(root, recipes):
    declared = {link["url"] for link in recipes["upstream_links"]}
    used = set()
    for path in root.rglob("*.md"):
        for href in markdown_links(path.read_text()):
            href = href.removeprefix("<").removesuffix(">")
            parsed = urlsplit(href)
            if parsed.scheme or parsed.netloc:
                if href.startswith(PREFIX):
                    if href not in declared:
                        raise ValueError(f"undeclared upstream link: {href}")
                    used.add(href)
                continue
            target = path.parent / unquote(parsed.path) if parsed.path else path
            if not target.resolve().is_relative_to(root.resolve()) or not target.exists():
                raise ValueError(f"broken or escaping relocated link: {path.relative_to(root)} -> {href}")
    if used != declared:
        raise ValueError("upstream link manifest differs from copied Markdown links")


def execute(repo, block, home, project):
    env = dict(os.environ, HOME=str(home), PROJECT_DIR=str(project))
    return subprocess.run(["bash", "-c", block], cwd=repo, env=env, text=True,
                          capture_output=True, timeout=20)


def verify_copy(repo, recipe, root, home, project):
    expected_paths = set()
    for artifact in recipe["artifacts"]:
        source = inside(repo, artifact["source"])
        destination = inside(root, artifact["destination"])
        if inventory(source) != inventory(destination):
            raise ValueError(f"copied artifact bytes/layout differ: {recipe['id']}:{artifact['destination']}")
        for relative in inventory(destination):
            current = destination if relative == "." else destination / relative
            expected_paths.add(str(current.relative_to(root)))
            expected_paths.update(str(p.relative_to(root)) for p in current.parents if p != root and p.is_relative_to(root))
    actual_paths = set(inventory(root)) - {"."}
    other = project if recipe["root"] == "home" else home
    if actual_paths != expected_paths or set(inventory(other)) != {"."}:
        raise ValueError(f"extra installed artifact or wrong root: {recipe['id']}")
    for dependency in recipe["runtime_dependencies"]:
        if not inside(root, dependency).is_file():
            raise ValueError(f"missing runtime dependency: {dependency}")
    check_links(root, recipe)


def collision_controls(repo, recipe, block):
    destinations = [artifact["destination"] for artifact in recipe["artifacts"]]
    parents = {str(p) for destination in destinations for p in PurePosixPath(destination).parents if str(p) != "."}
    for relative, kind in [(d, k) for d in destinations for k in ("file", "directory", "link", "dangling")]+[(p, "link") for p in sorted(parents)]:
        with tempfile.TemporaryDirectory(prefix="adoption collision ") as temporary:
            base = Path(temporary)
            home, project = base / "home space", base / "project space"
            home.mkdir(); project.mkdir()
            root = home if recipe["root"] == "home" else project
            target = inside(root, relative)
            target.parent.mkdir(parents=True, exist_ok=True)
            outside = base / "outside"
            outside.mkdir()
            if kind == "file":
                target.write_text("existing user configuration\n")
            elif kind == "directory":
                target.mkdir(); (target / "user.md").write_text("keep\n")
            else:
                target.symlink_to(outside if kind == "link" else base / "missing")
            before = inventory(base)
            result = execute(repo, block, home, project)
            if result.returncode == 0 or inventory(base) != before:
                raise ValueError(f"collision did not fail without changes: {recipe['id']}:{relative}:{kind}")


def check(repo, collision=True):
    for command in ("bash", "jq", "perl", "git", "cp", "mkdir"):
        if not shutil.which(command):
            raise ValueError(f"missing adoption dependency on PATH: {command}")
    recipes = load_manifest(repo)
    blocks = snippets(repo)
    for recipe in recipes:
        with tempfile.TemporaryDirectory(prefix="adoption copy ") as temporary:
            base = Path(temporary)
            home, project = base / "home space", base / "project space"
            home.mkdir(); project.mkdir()
            root = home if recipe["root"] == "home" else project
            result = execute(repo, blocks[recipe["id"]], home, project)
            if result.returncode:
                raise ValueError(f"recipe failed: {recipe['id']} ({result.returncode}): {result.stderr.strip()}")
            verify_copy(repo, recipe, root, home, project)
            before = inventory(base)
            repeat = execute(repo, blocks[recipe["id"]], home, project)
            if repeat.returncode == 0 or inventory(base) != before:
                raise ValueError(f"second run modified destination or accepted collision: {recipe['id']}")
        if collision:
            collision_controls(repo, recipe, blocks[recipe["id"]])
    return len(recipes)


def main():
    parser = argparse.ArgumentParser(description="Execute and verify the four documented copy recipes")
    parser.add_argument("--repo", type=Path, default=ROOT)
    args = parser.parse_args()
    try:
        count = check(args.repo.resolve())
        print(f"OK: {count} documented recipes, dependency layouts, relocated links and collision controls")
    except (OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError) as error:
        sys.exit(f"FAIL: {error}")


if __name__ == "__main__":
    main()
