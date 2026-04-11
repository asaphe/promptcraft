#!/usr/bin/env python3
"""
Skill eval runner — validates trigger and functional expectations.

Phase 1 (current): Manual mode — prints a checklist to run interactively in Claude Code.
Phase 3 (future): Automated mode via Claude Code SDK.

Usage:
  python runner.py                        # Run all evals (manual checklist)
  python runner.py --skill deploy         # Run one skill
  python runner.py --type trigger         # Trigger evals only
  python runner.py --type functional      # Functional evals only
"""

import argparse
import json
import sys
from datetime import datetime
from pathlib import Path

EVALS_DIR = Path(__file__).parent
_NON_SKILL_DIRS = {"reports", "__pycache__"}


def load_trigger_evals(skill_dir: Path) -> list[dict]:
    path = skill_dir / "trigger_eval.json"
    if not path.exists():
        return []
    return json.loads(path.read_text())


def load_functional_evals(skill_dir: Path) -> dict | None:
    path = skill_dir / "evals.json"
    if not path.exists():
        return None
    return json.loads(path.read_text())


def print_trigger_checklist(skill: str, evals: list[dict]) -> None:
    positives = [e for e in evals if e["should_trigger"]]
    negatives = [e for e in evals if not e["should_trigger"]]

    print(f"\n{'='*60}")
    print(f"TRIGGER EVAL: /{skill}")
    print(f"{'='*60}")
    print(f"\nIn a Claude Code session, test each query and mark pass/fail.\n")

    print(f"SHOULD trigger /{skill} ({len(positives)} cases):")
    for i, e in enumerate(positives, 1):
        print(f"  [{i}] Query: \"{e['query']}\"")
        print(f"       Expected: /{skill} activates")

    print(f"\nSHOULD NOT trigger /{skill} ({len(negatives)} cases):")
    for i, e in enumerate(negatives, 1):
        expected = e.get("expected_skill", "unknown")
        note = e.get("note", "")
        print(f"  [{i}] Query: \"{e['query']}\"")
        print(f"       Expected: /{expected} activates instead{' — ' + note if note else ''}")


def print_functional_checklist(skill: str, evals: dict) -> None:
    print(f"\n{'='*60}")
    print(f"FUNCTIONAL EVAL: /{skill}")
    print(f"{'='*60}")

    for ev in evals.get("evals", []):
        print(f"\n[Eval {ev['id']}] Prompt: \"{ev['prompt']}\"")
        if ev.get("setup"):
            print(f"  Setup: {ev['setup']}")
        print(f"  Expectations:")
        for i, exp in enumerate(ev["expectations"], 1):
            print(f"    [{i}] {exp}")
        if ev.get("teardown"):
            print(f"  Teardown: {ev['teardown']}")


def get_skill_dirs(skill_filter: str | None = None) -> list[Path]:
    dirs = sorted([
        d for d in EVALS_DIR.iterdir()
        if d.is_dir() and d.name not in _NON_SKILL_DIRS
    ])
    if skill_filter:
        dirs = [d for d in dirs if d.name == skill_filter]
    return dirs


def main() -> None:
    parser = argparse.ArgumentParser(description="Skill eval runner")
    parser.add_argument("--skill", help="Run evals for a specific skill only")
    parser.add_argument(
        "--type",
        choices=["trigger", "functional"],
        help="Run only trigger or functional evals",
    )
    args = parser.parse_args()

    skill_dirs = get_skill_dirs(args.skill)
    if not skill_dirs:
        print(
            f"No eval directories found"
            f"{' for skill: ' + args.skill if args.skill else ''}.",
            file=sys.stderr,
        )
        sys.exit(1)

    print(f"\nSkill Eval Runner — {datetime.now().strftime('%Y-%m-%d %H:%M')}")
    print(f"Mode: MANUAL (Phase 1) — run each query interactively in Claude Code")
    print(f"Skills: {', '.join(d.name for d in skill_dirs)}")

    for skill_dir in skill_dirs:
        skill = skill_dir.name

        if args.type in (None, "trigger"):
            evals = load_trigger_evals(skill_dir)
            if evals:
                print_trigger_checklist(skill, evals)

        if args.type in (None, "functional"):
            evals = load_functional_evals(skill_dir)
            if evals:
                print_functional_checklist(skill, evals)

    print(f"\n{'='*60}")
    print("Done. Mark each case as pass/fail in your test notes.")
    print(f"{'='*60}\n")


if __name__ == "__main__":
    main()
