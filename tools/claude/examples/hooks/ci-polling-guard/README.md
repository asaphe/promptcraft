# CI Polling Guard

A **PreToolUse** hook that blocks sleep-based CI polling loops and suggests background monitoring instead.

## Why

The single biggest source of wasted tool calls is CI polling: `sleep 30 && gh run view ...` repeated in a loop. In a data-mined analysis of 716 sessions, this pattern accounted for ~5,700 wasted calls and was the primary cause of a 13% bash command failure rate (timeouts, stale data).

The fix is simple: use `gh run watch --exit-status` with `run_in_background: true`. The agent gets notified when the run completes — no polling, no sleep, no wasted calls.

## Behavior

| Pattern | Action |
|---------|--------|
| `sleep N && gh run view ...` or `sleep N; gh pr checks ...` | Block with suggestion to use `gh run watch` |
| Bare `sleep N` where N >= 10 | Block with suggestion to use `run_in_background` |
| All other commands | Allow |

Uses soft blocking (JSON + exit 0). If you have `Bash(*)` in your allow list and want hard enforcement, change to `exit 2`.

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
            "command": "/path/to/ci-polling-guard.sh"
          }
        ]
      }
    ]
  }
}
```

## What Gets Blocked

```bash
# Blocked: sleep + poll loop
sleep 30 && gh run view 12345

# Blocked: bare long sleep (likely CI wait)
sleep 60

# Allowed: short sleep (< 10s, likely intentional)
sleep 2

# Allowed: direct status check (no sleep)
gh run view 12345
```

## The Better Pattern

Instead of polling, use background monitoring:

```bash
# Run in background — agent gets notified on completion
gh run watch 12345 --exit-status
# (with run_in_background: true on the Bash tool call)
```

This eliminates the polling loop entirely. The agent continues with other work and gets notified when the CI run finishes.
