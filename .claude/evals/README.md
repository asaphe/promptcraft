# Hook Evals

Automated test suite for the PreToolUse hooks in `.claude/hooks/`. Unlike skill evals (which require manual testing in Claude Code), hook evals are fully automated — the runner pipes JSON input through each hook and checks its exit code and output.

## Running

```bash
# All hooks
python .claude/evals/runner.py

# One hook
python .claude/evals/runner.py --hook destructive-guard

# Verbose (show passing cases)
python .claude/evals/runner.py --verbose
```

## Test Case Format

Each hook has a `cases.json`:

```json
[
  {
    "label": "human-readable description",
    "command": "the bash command to test",
    "expected_exit": 2,
    "expected_output": "substring that must appear in stdout or stderr",
    "expected_stdout": "substring that must appear on stdout specifically",
    "setup": "shell run before the hook, for cases needing real git state",
    "cleanup": "shell run after the hook, always",
    "note": "optional context about preconditions"
  }
]
```

- `expected_exit`: optional — 0 = allow, 2 = hard block. Soft blocks (JSON output) also exit 0. Omit to accept any exit code (useful for environment-dependent cases).
- `expected_output`: optional — if set, combined stdout+stderr must contain this substring. Use when the channel does not matter.
- `expected_stdout` / `expected_stderr`: optional — assert against one channel only. Use these when the channel *is* the behaviour under test. A reminder on exit 0 must land on stdout as `hookSpecificOutput.additionalContext`, because the harness discards stderr at exit 0; asserting it via `expected_output` alone would pass whether the hook works or is silently inert.
- `setup` / `cleanup`: optional shell snippets, run with `bash -c` before and after the hook. Use them when the behaviour under test depends on real git state — branch detection cannot be exercised without a repository to detect a branch in. A non-zero `setup` fails the case: without that, a fixture that was never created leaves the case passing for the wrong reason. `cleanup` runs in a `finally` that encloses `setup` as well as the hook, so it still tears down a partially-created fixture when `setup` fails or the hook times out.
- `note`: not checked by the runner, just documentation.

## Adding a case

Add the case, then mutation-test it: revert the rule it covers, confirm the case goes red, restore the file, and check it is byte-identical again (`shasum -a 256`). A case that stays green with its rule removed is asserting nothing — which is how a hook that never fires passes its own suite.

## When to Run

Run after modifying any hook in `.claude/hooks/`:

```bash
python .claude/evals/runner.py --hook <modified-hook-name>
```

## Coverage

| Hook | Cases | Tests |
|------|:-----:|-------|
| destructive-guard | 100 | push-to-main variants, refspec, hyphenated branches, force-push, bulk branch deletion, AWS two-tier, GH CLI incl. all three merge forms, terraform, kubectl, helm, and an adversarial-formatting axis (heredoc marker lines, tabs, line continuations) |
| stateful-op-reminder | 13 | kubectl apply/get, terraform apply/plan, helm upgrade/dry-run, IAM attach/list, safe command |
| pr-create-guard | 2 | pass-through, block on zero diff/missing prerequisites |

## See Also

For **skill routing validation** (manual testing of which Claude Code skill activates for a given query), see `../../tools/claude/examples/evals/`.

## Adding Cases

1. Add entries to `.claude/evals/{hook-name}/cases.json`
2. Run `python .claude/evals/runner.py --hook {hook-name} --verbose` to verify
3. Note: some cases depend on git state (e.g., "bare push from main" only fails when CWD is on main). Document preconditions in the `note` field.
