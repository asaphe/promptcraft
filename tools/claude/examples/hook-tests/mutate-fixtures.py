#!/usr/bin/env python3
"""Prove a fixture suite bites, by breaking the hook and requiring the suite to notice.

Usage: mutate-fixtures.py [--hooks-dir DIR] [--timeout S] [--shard K/N] [--jobs N] [--manifest F] [hook ...]
       (no hooks = every hook in mutations.json)

A fixture that has never been observed to fail is indistinguishable from one that
cannot fail. Guard fixtures are usually written by reading the hook, so the failure
mode is systematic rather than occasional: cases get written to agree with whatever
the hook already does, and a suite of those passes forever while asserting nothing.
This runs the suite against deliberately broken copies and requires each break to
be caught.

Mutations live in mutations.json as {file: [{why, delete_matching|replace, suite?}, ...]}.
The key names the file to mutate; `suite` names the fixture suite to run when that file is
a shared library with no suite of its own.
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

A third outcome is neither: a run whose only failures are TIMEOUTs says the host was slow,
not that the suite noticed the break. That run is INCONCLUSIVE and fails, because scoring it as
caught turns a loaded runner into a green step. Each suite runs with --fail-fast, so a caught
mutation stops at its first real failure instead of running every remaining case.

`--shard K/N` runs every Nth mutation starting at the Kth, so CI can split one long run.

A mutation's optional `witness` lists fixture rows, by column 2 as written, that caught it before;
they run first, so a caught mutation costs a case or two instead of every case ahead of its catch.
A witness that no longer catches costs nothing but time: the rest of the suite still runs, and
the run says the witness missed. `--record-witnesses OUT.json` writes each caught mutation's
first failing row, and `--apply-witnesses OUT.json ...` merges such files into the manifest.

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
import time

HERE = pathlib.Path(__file__).resolve().parent
MANIFEST = HERE / "mutations.json"
# run-fixtures.py's summary row for one mismatched case.
FAILURE_LINE = re.compile(r"^  want=[^\t\n]*\tgot=([^\t\n]*)\t", re.M)
# run-fixtures.py's --fail-fast stop row: the failing case's column 2 as written.
FIRST_FAILURE = re.compile(r"^first failure: (.*)$", re.M)


def apply_witnesses(manifest_path, recorded_paths):
    """Merges --record-witnesses files into the manifest, replacing each recorded mutation's witness."""
    manifest = json.loads(pathlib.Path(manifest_path).read_text())
    count = 0
    for path in recorded_paths:
        for hook, entries in json.loads(pathlib.Path(path).read_text()).items():
            for index, row in entries.items():
                manifest[hook][int(index)]["witness"] = [row]
                count += 1
    pathlib.Path(manifest_path).write_text(json.dumps(manifest, indent=2) + "\n")
    print("%d witnesses written to %s" % (count, manifest_path))


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


def resolve_target(hooks_dir, name):
    if name.startswith("_lib/"):
        target = hooks_dir / name
        if target.is_file():
            return target
    return resolve_hook(hooks_dir, name)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("hooks", nargs="*")
    ap.add_argument("--hooks-dir", default=str(HERE.parent))
    # A per-case TIMEOUT fails the suite too, so on a loaded host it would score every mutation as caught.
    ap.add_argument("--timeout", help="per-case timeout passed to run-fixtures.py")
    ap.add_argument("--shard", default="1/1", help="K/N: run every Nth mutation, starting at the Kth")
    ap.add_argument("--jobs", help="cases each suite runs at once, passed to run-fixtures.py")
    ap.add_argument("--manifest", default=str(MANIFEST))
    ap.add_argument("--record-witnesses", metavar="OUT.json",
                    help="write each caught mutation's first failing row here, for --apply-witnesses")
    ap.add_argument("--apply-witnesses", nargs="+", metavar="OUT.json",
                    help="merge recorded witness files into --manifest and exit")
    args = ap.parse_args()
    if args.apply_witnesses:
        apply_witnesses(args.manifest, args.apply_witnesses)
        return
    shard = re.fullmatch(r"([1-9][0-9]*)/([1-9][0-9]*)", args.shard)
    if not shard or int(shard.group(1)) > int(shard.group(2)):
        sys.exit("--shard must be K/N with 1 <= K <= N: %r" % args.shard)
    shard_k, shard_n = int(shard.group(1)) - 1, int(shard.group(2))

    manifest = {k: v for k, v in json.loads(pathlib.Path(args.manifest).read_text()).items()
                if k != "_README"}
    wanted = args.hooks or sorted(manifest)
    unknown = [h for h in wanted if h not in manifest]
    if unknown:
        sys.exit("no mutations defined for: %s" % ", ".join(unknown))

    src = pathlib.Path(args.hooks_dir).expanduser().resolve()
    tmp = pathlib.Path(tempfile.mkdtemp(prefix="mutate-hooks-"))
    tree = tmp / "hooks"
    shutil.copytree(src, tree)

    failures, total, position, missed, recorded = [], 0, -1, 0, {}
    for hook in wanted:
        target = resolve_target(tree, hook)
        pristine = target.read_text()
        for index, mutation in enumerate(manifest[hook]):
            position += 1
            if position % shard_n != shard_k:
                continue
            total += 1
            broken = apply_mutation(pristine, mutation)
            if broken == pristine:
                failures.append((hook, mutation["why"],
                                 "mutation changed nothing — its pattern has drifted out of the hook"))
                print("FAIL %s: INERT MUTATION — %s" % (hook, mutation["why"]))
                continue
            target.write_text(broken)
            # A shared library has no suite of its own; run one that consumes it.
            suite = mutation.get("suite", hook)
            cmd = [sys.executable, str(HERE / "run-fixtures.py"), suite, "--hooks-dir", str(tree),
                   "--fail-fast"]
            if args.timeout:
                cmd += ["--timeout", args.timeout]
            if args.jobs:
                cmd += ["--jobs", args.jobs]
            witness = mutation.get("witness", [])
            for row in witness:
                cmd += ["--first", row]
            started = time.monotonic()
            proc = subprocess.run(cmd, capture_output=True, text=True)
            took = time.monotonic() - started
            target.write_text(pristine)
            got = [m.group(1) for m in FAILURE_LINE.finditer(proc.stdout)]
            caught = proc.returncode != 0 and any(g != "TIMEOUT" for g in got)
            first = FIRST_FAILURE.search(proc.stdout)
            stale = ""
            if caught and first:
                recorded.setdefault(hook, {})[str(index)] = first.group(1)
                if witness and first.group(1) not in witness:
                    missed += 1
                    stale = ", witness missed"
            tally = next((ln for ln in proc.stdout.splitlines() if "passed" in ln), "?")
            label = "ok  " if caught else ("FAIL" if proc.returncode == 0 else "INCONCLUSIVE")
            print("%s %s: %s  [%s, %.0fs%s]" % (label, hook, mutation["why"], tally.strip(), took, stale),
                  flush=True)
            if proc.returncode == 0:
                failures.append((hook, mutation["why"], "suite still passed with the hook broken"))
            elif not caught:
                failures.append((hook, mutation["why"],
                                 "INCONCLUSIVE: the suite failed only on timeouts or on its own error"
                                 " (exit %d), so it never showed the break; raise --timeout"
                                 % proc.returncode))

    shutil.rmtree(tmp, ignore_errors=True)
    if args.record_witnesses:
        pathlib.Path(args.record_witnesses).write_text(json.dumps(recorded, indent=2) + "\n")
    print("\n%d/%d mutations caught" % (total - len(failures), total))
    if missed:
        print("%d witness(es) missed: the suite still caught them; refresh with --record-witnesses" % missed)
    if failures:
        print("\nNOT CAUGHT:")
        for hook, why, how in failures:
            print("  %s: %s — %s" % (hook, why, how))
        sys.exit(1)


if __name__ == "__main__":
    main()
