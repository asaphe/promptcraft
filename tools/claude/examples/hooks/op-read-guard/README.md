# 1Password Read Guard

A **PreToolUse** hook that blocks duplicate `op read` and `op item get` calls within the same session.

## Why

Every `op read` call triggers a biometric prompt (Touch ID, password). The AI agent has no awareness that it already read the same secret earlier in the session — it just calls `op read` again, forcing the user to authenticate again.

In practice, the same secret gets read 3-5 times per session: once to check its value, once to compare with something, once to set an env var, etc. This hook blocks the duplicates with a reminder to reuse the cached value.

## Behavior

| Situation | Action |
|-----------|--------|
| First `op read` for a secret | Allow + record the reference |
| Second+ `op read` for same secret | Block with "reuse cached value" message |
| `op read` for a different secret | Allow + record |
| Non-op commands | Allow |

## Setup

Register as a PreToolUse hook on `Bash` in `~/.claude/settings.json`:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "/path/to/op-read-guard.sh"
          }
        ]
      }
    ]
  }
}
```

## State Tracking

Uses a session-scoped temp file (`/tmp/claude-op-reads-<session-id>`) to track which secrets have been read. The file is keyed by `CLAUDE_SESSION_ID`, which Claude Code sets automatically.

### Why Not `$$` (PID)?

Each hook invocation runs in a new subprocess with a different PID. Using `$$` would create a new tracking file per invocation, defeating deduplication entirely. `CLAUDE_SESSION_ID` persists across the entire session.

## Companion Rules

This hook works best with a CLAUDE.md rule that tells the agent to cache secret values:

```markdown
- **1Password token reuse** — NEVER call `op read` more than once per secret per session.
  Each call prompts for biometric approval. On first use, read the secret and remember
  the value. For subsequent Bash calls, re-export the remembered value.
```

The hook enforces the rule deterministically; the rule teaches the agent *why* and how to work around it.
