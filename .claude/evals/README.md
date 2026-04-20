# Hook Evals

Automated test suite for the PreToolUse hooks in `.claude/hooks/`. Unlike skill evals (which require manual testing in Claude Code), hook evals are fully automated — the runner pipes JSON input through each hook and checks exit codes and stderr.

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
    "note": "optional context about preconditions"
  }
]
```

- `expected_exit`: optional — 0 = allow, 2 = hard block. Soft blocks (JSON output) also exit 0. Omit to accept any exit code (useful for environment-dependent cases).
- `expected_output`: optional — if set, combined stdout+stderr must contain this substring. Covers both hard blocks (stderr) and soft blocks (JSON on stdout).
- `note`: not checked by the runner, just documentation.

## When to Run

Run after modifying any hook in `.claude/hooks/`:

```bash
python .claude/evals/runner.py --hook <modified-hook-name>
```

## Coverage

| Hook | Cases | Tests |
|------|:-----:|-------|
| destructive-guard | 21 | push-to-main variants, refspec, hyphenated branches, force-push, AWS, GH CLI, terraform, kubectl, helm |
| stateful-op-reminder | 9 | kubectl apply/get, terraform apply/plan, helm upgrade/dry-run, IAM attach/list, safe command |
| pr-create-guard | 2 | pass-through, block on zero diff/missing prerequisites |

## See Also

For **skill routing validation** (manual testing of which Claude Code skill activates for a given query), see `../../tools/claude/examples/evals/`.

## Adding Cases

1. Add entries to `.claude/evals/{hook-name}/cases.json`
2. Run `python .claude/evals/runner.py --hook {hook-name} --verbose` to verify
3. Note: some cases depend on git state (e.g., "bare push from main" only fails when CWD is on main). Document preconditions in the `note` field.
