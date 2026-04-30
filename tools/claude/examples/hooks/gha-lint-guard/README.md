# gha-lint-guard

Runs `actionlint` on staged `.github/workflows/*.yaml` files at `git commit` time. Blocks the commit on failure.

## Why this exists

`actionlint` catches GitHub Actions errors that aren't visible until a workflow run actually fails:

- Step / job IDs with hyphens (GHA expression engine treats `-` as minus)
- `environment:` on `uses:` jobs (rejected at workflow-load time)
- Unknown runner labels (silent fallback to `ubuntu-latest`)
- Shell expression typos
- Unpinned action references (with a config file allowing internal `@main` exceptions)

Catching these at commit time avoids the round-trip of pushing, watching the workflow fail, fixing, and re-pushing.

## What it does

1. Triggered on any `git commit` (flag-permissive: catches `git -C dir commit`, etc.)
2. If a worktree is referenced via `-C`, `cd`s into that worktree first
3. Inspects `git diff --cached --name-only` for staged `.github/workflows/*.ya?ml`
4. If no workflow files are staged → exit 0 (allow)
5. If `actionlint` is not installed → log and exit 0 (don't punish missing tool)
6. Runs `actionlint` with `-config-file .github/actionlint.yaml` if present
7. On failure: prints actionlint output to stderr, exits 2 (hard block)

## Configuration

Install actionlint:

```bash
brew install actionlint           # macOS
# or download from https://github.com/rhysd/actionlint/releases
```

Optional `actionlint.yaml` at repo root (e.g. for enterprise runner labels):

```yaml
self-hosted-runner:
  labels:
    - ubuntu-latest-m
```

Add to `.claude/settings.json`:

```jsonc
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": "/absolute/path/to/gha-lint-guard.sh" }
        ]
      }
    ]
  }
}
```

## Exit codes

| Exit | Meaning |
|------|---------|
| 0 | Allow — not a commit, no workflow files staged, actionlint missing, or actionlint passed |
| 2 | Hard block — actionlint failed on staged workflow files |

## Pairs well with

- `zizmor` security pre-commit (template injection, unpinned refs, excessive permissions) — run as a separate hook with the same gate shape
