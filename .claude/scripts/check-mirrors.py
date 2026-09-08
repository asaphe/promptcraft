#!/usr/bin/env python3
"""Fail if a dogfooded copy under .claude/ has drifted from its published example.

The repo ships each hook twice: `tools/claude/examples/...` is the artifact people copy,
`.claude/...` is the copy this repo runs and the only one the eval suite exercises. A fix
applied to one and not the other is invisible — the suite stays green against the copy that
was fixed while adopters get the copy that was not.

Invariant: every file under .claude/_lib and .claude/hooks that has an examples counterpart
must be byte-identical to it. Examples-only files are fine (nothing here consumes them).

Run: python3 .claude/scripts/check-mirrors.py
"""
from __future__ import annotations

import hashlib
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
EX_LIB = ROOT / "tools/claude/examples/hooks/_lib"
EX_HOOKS = ROOT / "tools/claude/examples/hooks"

PAIRS: list[tuple[Path, Path]] = []
for f in sorted((ROOT / ".claude/_lib").glob("*")):
    if f.is_file():
        PAIRS.append((f, EX_LIB / f.name))
for f in sorted((ROOT / ".claude/hooks").glob("*.sh")):
    counterpart = EX_HOOKS / f.stem / f.name
    if counterpart.exists():
        PAIRS.append((f, counterpart))


def digest(p: Path) -> str:
    return hashlib.sha256(p.read_bytes()).hexdigest()


def main() -> None:
    if not PAIRS:
        sys.exit("FAIL: no mirror pairs discovered — this checker is not checking anything")

    drift, missing = [], []
    for local, example in PAIRS:
        rel = local.relative_to(ROOT)
        if not example.exists():
            missing.append(f"{rel} has no counterpart at {example.relative_to(ROOT)}")
        elif digest(local) != digest(example):
            drift.append(f"{rel} != {example.relative_to(ROOT)}")

    if missing or drift:
        for line in missing + drift:
            print(f"  {line}", file=sys.stderr)
        sys.exit(
            f"FAIL: {len(drift)} drifted, {len(missing)} unpaired. The .claude/ copy is what the "
            "eval suite runs; the examples copy is what people install. They must not diverge."
        )

    print(f"OK: {len(PAIRS)} mirror pairs byte-identical")


if __name__ == "__main__":
    main()
