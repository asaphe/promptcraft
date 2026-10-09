#!/usr/bin/env python3

import argparse
from pathlib import Path, PurePosixPath
import subprocess
import sys
import uuid


def tracked_markdown(repo):
    result = subprocess.run(
        ["git", "ls-files", "-z"], cwd=repo, check=True, capture_output=True
    )
    paths = result.stdout.decode("utf-8").split("\0")
    selected = set()
    for path in paths:
        if path and PurePosixPath(path).suffix in {".md", ".markdown"}:
            validate_path(path)
            selected.add(path)
    return selected


def validate_path(path):
    relative = PurePosixPath(path)
    if (not path or relative.is_absolute() or ".." in relative.parts
            or str(relative) != path or any(c in path for c in "\n\r\0")):
        raise ValueError(f"unsupported Markdown path: {path!r}")


def lint_inputs(repo):
    tracked = tracked_markdown(repo)
    exclusions = set()
    for entry in (repo / ".markdownlintignore").read_text().split("\n"):
        if not entry.strip() or entry.startswith("#"):
            continue
        validate_path(entry)
        if entry.startswith("!") or any(c in entry for c in "*?[]{}\\"):
            raise ValueError(f"unsupported exclusion: {entry!r}")
        if entry not in tracked or entry in exclusions:
            raise ValueError(f"exclusion must name one tracked Markdown file: {entry!r}")
        exclusions.add(entry)
    selected = sorted(tracked - exclusions)
    if not selected:
        raise ValueError("empty tracked Markdown corpus after exclusions")
    return "".join(f":{path}\n" for path in selected)


def main():
    parser = argparse.ArgumentParser(description="Emit tracked Markdown as CLI2 literal inputs")
    parser.add_argument("--repo", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--github-output", type=Path)
    args = parser.parse_args()
    try:
        output = lint_inputs(args.repo)
        if args.github_output:
            delimiter = "markdownlint_" + uuid.uuid4().hex
            with args.github_output.open("a", encoding="utf-8") as stream:
                stream.write(f"globs<<{delimiter}\n{output}{delimiter}\n")
        sys.stdout.write(output)
    except (OSError, ValueError, subprocess.CalledProcessError, UnicodeError) as error:
        sys.exit(f"FAIL: {error}")


if __name__ == "__main__":
    main()
