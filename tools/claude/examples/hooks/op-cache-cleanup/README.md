# op-cache-cleanup

`Stop` hook that purges the per-session 1Password value cache when Claude Code's session ends.

## Why this exists

The companion script `examples/scripts/op-cache.sh` caches `op read` results in `/tmp/op-cache-<session>/` so the user isn't biometric-prompted on every Bash call within the session. Without this cleanup hook, those cached values sit on disk until the next OS reboot. This hook removes them as soon as the session ends.

## What it does

1. Reads the Stop hook payload from stdin
2. Extracts `session_id` via `jq`
3. `rm -rf /tmp/op-cache-${session_id}`
4. Exits 0 unconditionally — Stop hooks shouldn't block

## Configuration

Add to `.claude/settings.json`:

```jsonc
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          { "type": "command", "command": "/absolute/path/to/op-cache-cleanup.sh" }
        ]
      }
    ]
  }
}
```

## Pairs with

- `examples/scripts/op-cache.sh` — the cache producer
- `examples/docs/1password-caching.md` — full pattern docs
