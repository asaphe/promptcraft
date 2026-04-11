#!/usr/bin/env python3
"""
Hook eval runner — automated testing for PreToolUse hook scripts.

Unlike skill evals (which require manual testing in Claude Code), hook evals
are fully automated: pipe JSON input through the hook, check exit code and
stderr against expectations.

Usage:
  python runner.py                          # Run all hook evals
  python runner.py --hook destructive-guard # Run one hook
  python runner.py --verbose                # Show passing cases too
"""

import argparse
import json
import subprocess
import sys
from pathlib import Path

EVALS_DIR = Path(__file__).parent
HOOKS_DIR = EVALS_DIR.parent / "hooks"
_NON_HOOK_DIRS = {"__pycache__"}


def load_cases(hook_dir: Path) -> list[dict]:
    path = hook_dir / "cases.json"
    if not path.exists():
        return []
    return json.loads(path.read_text())


def run_hook(hook_path: Path, command: str) -> tuple[int, str]:
    """Run a hook with a simulated tool_input and return (exit_code, combined_output).

    Combines stdout and stderr since hooks use different channels:
    - Hard blocks: stderr (exit 2)
    - Soft blocks: stdout JSON with permissionDecision (exit 0)
    - Reminders: stderr (exit 0)
    """
    input_json = json.dumps({"tool_input": {"command": command}})
    result = subprocess.run(
        [str(hook_path)],
        input=input_json,
        capture_output=True,
        text=True,
        timeout=10,
    )
    combined = (result.stdout.strip() + "\n" + result.stderr.strip()).strip()
    return result.returncode, combined


def check_case(hook_path: Path, case: dict) -> tuple[bool, str]:
    """Run one test case and return (passed, detail)."""
    command = case["command"]
    expected_exit = case.get("expected_exit")
    expected_output = case.get("expected_output")

    try:
        exit_code, combined = run_hook(hook_path, command)
    except subprocess.TimeoutExpired:
        return False, "TIMEOUT (>10s)"
    except FileNotFoundError:
        return False, f"Hook not found: {hook_path}"

    if expected_exit is not None and exit_code != expected_exit:
        return False, f"exit {exit_code} (expected {expected_exit}), output: {combined}"

    if expected_output and expected_output not in combined:
        return False, (
            f"exit {exit_code} OK, but output missing expected text.\n"
            f"  Expected substring: {expected_output}\n"
            f"  Actual output: {combined}"
        )

    return True, f"exit {exit_code}, output: {combined[:80]}" if combined else f"exit {exit_code}"


def get_hook_dirs(hook_filter: str | None = None) -> list[Path]:
    dirs = sorted([
        d for d in EVALS_DIR.iterdir()
        if d.is_dir() and d.name not in _NON_HOOK_DIRS
    ])
    if hook_filter:
        dirs = [d for d in dirs if d.name == hook_filter]
    return dirs


def main() -> None:
    parser = argparse.ArgumentParser(description="Hook eval runner")
    parser.add_argument("--hook", help="Run evals for a specific hook only")
    parser.add_argument("--verbose", action="store_true", help="Show passing cases")
    args = parser.parse_args()

    hook_dirs = get_hook_dirs(args.hook)
    if not hook_dirs:
        print(
            f"No eval directories found"
            f"{' for hook: ' + args.hook if args.hook else ''}.",
            file=sys.stderr,
        )
        sys.exit(1)

    total_pass = 0
    total_fail = 0
    failures = []

    for hook_dir in hook_dirs:
        hook_name = hook_dir.name
        hook_path = HOOKS_DIR / f"{hook_name}.sh"

        if not hook_path.exists():
            print(f"\nSKIP: {hook_name} — hook not found at {hook_path}")
            continue

        cases = load_cases(hook_dir)
        if not cases:
            print(f"\nSKIP: {hook_name} — no cases.json found")
            continue

        print(f"\n{'='*60}")
        print(f"HOOK EVAL: {hook_name} ({len(cases)} cases)")
        print(f"{'='*60}")

        for i, case in enumerate(cases, 1):
            passed, detail = check_case(hook_path, case)
            label = case.get("label", case["command"][:60])

            if passed:
                total_pass += 1
                if args.verbose:
                    print(f"  PASS [{i}] {label}")
                    print(f"         {detail}")
            else:
                total_fail += 1
                failures.append((hook_name, i, label, detail))
                print(f"  FAIL [{i}] {label}")
                print(f"         {detail}")

    print(f"\n{'='*60}")
    print(f"Results: {total_pass} passed, {total_fail} failed")
    if failures:
        print(f"\nFailures:")
        for hook, idx, label, detail in failures:
            print(f"  [{hook}:{idx}] {label}")
            print(f"    {detail}")
    print(f"{'='*60}\n")

    sys.exit(1 if total_fail > 0 else 0)


if __name__ == "__main__":
    main()
