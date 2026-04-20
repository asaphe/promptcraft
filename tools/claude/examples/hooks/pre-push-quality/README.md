# Pre-Push Quality Gate

A comprehensive PreToolUse hook that intercepts `git push` and blocks it if any linter, formatter, or validation check fails. Combines lint enforcement with stale reference detection.

## What it checks

| Check | Tool | Blocking? |
|-------|------|-----------|
| Scope mixing (app + infra) | git diff | Warning (blocks) |
| Python lint + format | ruff | Blocks on errors |
| Terraform format | terraform fmt | Blocks on unformatted |
| Shell scripts | shellcheck | Blocks on errors |
| Dockerfiles | hadolint | Blocks on errors |
| GitHub Actions | actionlint | Blocks on errors |
| Stale .md references | grep | Blocks if deleted file still referenced |

## How it blocks

Uses the Claude Code `PreToolUse` JSON response to block the push and feed the failure reason back to Claude:

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "block",
    "permissionDecisionReason": "git push BLOCKED — quality gate failures..."
  }
}
```

Claude receives the failure reason and can self-correct before retrying the push.

## Design decisions

- **Matcher is `Bash`**, not just `git push` — the hook reads stdin and filters to `git push` internally. This is because Claude Code matchers match on tool name, not command content.
- **Skips force-push** — Destructive operations are handled by a separate `destructive-guard` hook.
- **Scope warning** — Detects PRs that mix app code (`python/`, `typescript/`) with infra (`devops/`, `.github/`), which usually indicates a dirty worktree.
- **Stale ref detection** — Checks if any deleted `.md` file is still referenced in `.claude/` docs.

## Customization

- Add/remove linter sections to match your tech stack
- Adjust directory patterns in the scope check for your monorepo layout
- Tune `grep` patterns for stale reference detection

## Layer

**Global** (`~/.claude/settings.json`) — Personal quality bar. Each developer can customize their gate. Some may want stricter checks, others may skip certain linters.
