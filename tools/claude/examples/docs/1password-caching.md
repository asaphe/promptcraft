# 1Password Per-Session Value Caching

Pattern for avoiding repeated biometric / `op signin` prompts when reading 1Password secrets across multiple Bash tool calls within a single Claude Code session.

## Convention

**Never call `op read` more than once per secret per session.** Each call prompts the user for biometric approval — even with a valid `op` session, the touch-ID prompt fires on every read.

On first use, read the secret and remember the value. For all subsequent Bash calls needing that secret, re-export the remembered value — do not call `op read` again. Each Bash tool call is a fresh shell, so `export` doesn't persist, but the value itself can be reused.

## Mechanical enforcement

Use the `op-cache.sh` wrapper (`examples/scripts/op-cache.sh`) as a drop-in replacement for `op read`. It hashes the URI, caches the value under `/tmp/op-cache-<session>/<sha256>`, and serves cached reads without re-invoking `op`.

```bash
# First call: reads from 1Password, caches, returns value
TOKEN=$(~/.claude/scripts/op-cache.sh op://Vault/Item/field)

# Second and subsequent calls (same URI): served from cache, no biometric prompt
TOKEN=$(~/.claude/scripts/op-cache.sh op://Vault/Item/field)

# Force a fresh read (e.g., secret rotated mid-session)
TOKEN=$(~/.claude/scripts/op-cache.sh --refresh op://Vault/Item/field)
```

The cache directory uses session ID (`CLAUDE_SESSION_ID` env var, falls back to `pid-<PPID>`). Files are mode 600 inside a 700 directory.

## Cleanup

Pair the wrapper with the `op-cache-cleanup` Stop hook (`examples/hooks/op-cache-cleanup/`). The hook removes `/tmp/op-cache-<session>/` when Claude Code's session ends, so cached values don't sit on disk until reboot.

## `op` CLI gotchas

### Item naming with special characters

`op read` URIs do not support square brackets or other special characters in item names. Use hyphens instead in your item titles. If an item already has special characters, fall back to `op item get <id> --fields <field>` by item ID.

### `--reveal` for concealed fields

`op item get --fields <field>` returns the literal placeholder `[use 'op item get' to reveal]` for concealed fields (passwords, tokens). Always use `--reveal` when reading values programmatically:

```bash
op item get '<item>' --fields '<field>' --reveal
```

The `op-cache.sh` wrapper handles this correctly because it uses `op read`, which always reveals.

## Related

- `examples/scripts/op-cache.sh` — the wrapper
- `examples/hooks/op-cache-cleanup/` — the Stop hook for end-of-session cleanup
