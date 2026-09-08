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
import os
import subprocess
import sys
import tempfile
from pathlib import Path

EVALS_DIR = Path(__file__).parent
HOOKS_DIR = EVALS_DIR.parent / "hooks"
_NON_HOOK_DIRS = {"__pycache__"}


def load_cases(hook_dir: Path) -> list[dict]:
    path = hook_dir / "cases.json"
    if not path.exists():
        return []
    return json.loads(path.read_text())


def run_hook(hook_path: Path, command: str) -> tuple[int, str, str]:
    """Run a hook with a simulated tool_input and return (exit_code, stdout, stderr).

    The channel a hook writes to is load-bearing, not cosmetic:
    - Hard blocks: stderr (exit 2) — the harness shows stderr to the model
    - Soft blocks: stdout JSON with permissionDecision (exit 0)
    - Reminders: stdout JSON with hookSpecificOutput.additionalContext (exit 0),
      because on exit 0 the harness discards stderr entirely

    Cases assert against the union via `expected_output`, or against one channel
    via `expected_stdout` / `expected_stderr` when the channel is the point.
    """
    input_json = json.dumps({"tool_input": {"command": command}})
    # Redirected: without this the suite appends its synthetic commands to the real diagnostic
    # corpora, polluting the very logs those overrides exist to keep clean.
    with tempfile.TemporaryDirectory(prefix="hook-eval-logs-") as logdir:
        env = {
            **os.environ,
            "HOOK_DIAG_LOG": str(Path(logdir) / "diag.log"),
            "HOOK_DIAG_ALLOW_LOG": str(Path(logdir) / "allow.log"),
            "HOOK_DIAG_ASK_LOG": str(Path(logdir) / "ask.log"),
        }
        result = subprocess.run(
            [str(hook_path)],
            input=input_json,
            capture_output=True,
            text=True,
            timeout=10,
            env=env,
        )
    return result.returncode, result.stdout.strip(), result.stderr.strip()


def run_fixture(script: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        ["bash", "-c", script], capture_output=True, text=True, timeout=30
    )


def check_case(hook_path: Path, case: dict) -> tuple[bool, str]:
    """Run one test case and return (passed, detail).

    A case may carry `setup`/`cleanup` shell snippets when the behaviour under test
    depends on real git state — branch detection cannot be exercised without a repo.
    A failing setup fails the case: without that, the fixture is silently absent and
    the case passes for the wrong reason.
    """
    command = case["command"]
    expected_exit = case.get("expected_exit")

    try:
        if case.get("setup"):
            setup = run_fixture(case["setup"])
            if setup.returncode != 0:
                return False, f"SETUP FAILED (exit {setup.returncode}): {setup.stderr.strip()[:200]}"
        exit_code, stdout, stderr = run_hook(hook_path, command)
    except subprocess.TimeoutExpired:
        return False, "TIMEOUT (>10s)"
    except FileNotFoundError:
        return False, f"Hook not found: {hook_path}"
    finally:
        # Inside the same try as setup: a partially-created fixture still needs tearing down.
        if case.get("cleanup"):
            run_fixture(case["cleanup"])

    combined = (stdout + "\n" + stderr).strip()

    if expected_exit is not None and exit_code != expected_exit:
        return False, f"exit {exit_code} (expected {expected_exit}), output: {combined}"

    # `expected_exit: 0` alone cannot tell an allow from a soft-block ask — both exit 0 — so a
    # negative control asserting only the exit code stays green when its rule starts over-firing.
    if case.get("expected_silent") and combined:
        return False, (
            f"exit {exit_code} OK, but expected a SILENT allow and got output.\n"
            f"  stdout: {stdout[:200]}\n  stderr: {stderr[:200]}"
        )

    for field, actual, label in (
        ("expected_output", combined, "output"),
        ("expected_stdout", stdout, "stdout"),
        ("expected_stderr", stderr, "stderr"),
    ):
        expected = case.get(field)
        if expected and expected not in actual:
            return False, (
                f"exit {exit_code} OK, but {label} missing expected text.\n"
                f"  Expected substring: {expected}\n"
                f"  Actual {label}: {actual}"
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
