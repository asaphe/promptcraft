#!/usr/bin/env python3
"""Prove a fixture suite bites, by breaking the hook and requiring the suite to notice.

Usage: mutate-fixtures.py [--hooks-dir DIR] [hook ...]   (no hooks = every hook in mutations.json)

A fixture that has never been observed to fail is indistinguishable from one that
cannot fail. Guard fixtures are usually written by reading the hook, so the failure
mode is systematic rather than occasional: cases get written to agree with whatever
the hook already does, and a suite of those passes forever while asserting nothing.
This runs the suite against deliberately broken copies and requires each break to
be caught.

Mutations live in mutations.json as {hook: [{why, delete_matching|replace}, ...]}.
Aim each one at a distinct behaviour — one that kills a block branch, one that kills
a false-positive defence — because a single "neuter the whole hook" mutation only
proves the suite notices a corpse.

Two things are checked per mutation, and the second is the one that matters:

  1. The broken hook fails its suite.
  2. The mutation actually changed the file.

Without (2), a mutation whose pattern has drifted out of the hook silently applies to
nothing, the pristine hook passes its own suite, and the run reports the fixture as
vacuous when the truth is that the mutation was. That reads as a real finding and
sends you off to rewrite a fixture that was fine.

The copy is a whole tree under a temp dir, so the live hooks are never edited.
"""

import argparse
import json
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile

HERE = pathlib.Path(__file__).resolve().parent
MANIFEST = HERE / "mutations.json"


def apply_mutation(text, mutation):
    if "delete_matching" in mutation:
        pattern = re.compile(mutation["delete_matching"])
        return "\n".join(ln for ln in text.split("\n") if not pattern.search(ln))
    if "replace" in mutation:
        return text.replace(mutation["replace"]["from"], mutation["replace"]["to"])
    sys.exit("mutation needs delete_matching or replace: %s" % mutation)


def resolve_hook(hooks_dir, name):
    for candidate in (hooks_dir / ("%s.sh" % name), hooks_dir / name / ("%s.sh" % name)):
        if candidate.is_file():
            return candidate
    sys.exit("no hook %r under %s" % (name, hooks_dir))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("hooks", nargs="*")
    ap.add_argument("--hooks-dir", default=str(HERE.parent))
    args = ap.parse_args()

    manifest = {k: v for k, v in json.loads(MANIFEST.read_text()).items()
                if not k.startswith("_")}
    wanted = args.hooks or sorted(manifest)
    unknown = [h for h in wanted if h not in manifest]
    if unknown:
        sys.exit("no mutations defined for: %s" % ", ".join(unknown))

    src = pathlib.Path(args.hooks_dir).expanduser().resolve()
    tmp = pathlib.Path(tempfile.mkdtemp(prefix="mutate-hooks-"))
    tree = tmp / "hooks"
    shutil.copytree(src, tree)

    failures, total = [], 0
    for hook in wanted:
        target = resolve_hook(tree, hook)
        pristine = target.read_text()
        for mutation in manifest[hook]:
            total += 1
            broken = apply_mutation(pristine, mutation)
            if broken == pristine:
                failures.append((hook, mutation["why"],
                                 "mutation changed nothing — its pattern has drifted out of the hook"))
                print("FAIL %s: INERT MUTATION — %s" % (hook, mutation["why"]))
                continue
            target.write_text(broken)
            proc = subprocess.run(
                [sys.executable, str(HERE / "run-fixtures.py"), hook, "--hooks-dir", str(tree)],
                capture_output=True, text=True,
            )
            target.write_text(pristine)
            caught = proc.returncode != 0
            tally = next((ln for ln in proc.stdout.splitlines() if "passed" in ln), "?")
            print("%s %s: %s  [%s]" % ("ok  " if caught else "FAIL", hook,
                                       mutation["why"], tally.strip()))
            if not caught:
                failures.append((hook, mutation["why"], "suite still passed with the hook broken"))

    shutil.rmtree(tmp, ignore_errors=True)
    print("\n%d/%d mutations caught" % (total - len(failures), total))
    if failures:
        print("\nNOT CAUGHT:")
        for hook, why, how in failures:
            print("  %s: %s — %s" % (hook, why, how))
        sys.exit(1)


if __name__ == "__main__":
    main()
