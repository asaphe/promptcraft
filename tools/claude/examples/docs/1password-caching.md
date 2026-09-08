# 1Password Per-Session Value Caching

Pattern for avoiding repeated biometric / `op signin` prompts when reading 1Password secrets across multiple Bash tool calls within a single Claude Code session.

## Convention

**Never call `op read` more than once per secret per session.** Each call prompts the user for biometric approval — even with a valid `op` session, the touch-ID prompt fires on every read.

On first use, read the secret and remember the value. For all subsequent Bash calls needing that secret, re-export the remembered value — do not call `op read` again. Each Bash tool call is a fresh shell, so `export` doesn't persist, but the value itself can be reused.

## Mechanical enforcement

The wrapper and its cleanup hook that used to ship here now live in
**[claude-secret-guard](https://github.com/asaphe/claude-secret-guard)** as
`scripts/op-cache.sh` and `scripts/op-cache-cleanup.sh`:

```text
/plugin marketplace add asaphe/claude-secret-guard
/plugin install secret-guard@claude-secret-guard
```

`op-cache.sh` is a drop-in replacement for `op read` that fetches once per session and caches
under `/tmp/op-cache-<session>/`, mode 600 inside a 700 directory. It prints a masked
confirmation and the cache path rather than the value — reference it downstream as
`$(cat <printed-path>)`:

```bash
# First call: reads from 1Password, caches, prints a masked confirmation + path
op-cache.sh op://Vault/Item/field

# Downstream use — the value never enters the transcript
TOKEN=$(cat /tmp/op-cache-<session>/<sha256>)

# Print the real value when you genuinely need to see it (checking a format)
op-cache.sh --reveal op://Vault/Item/field

# Force a fresh read (secret rotated mid-session)
op-cache.sh --refresh op://Vault/Item/field
```

Masking is the part worth keeping. A cache that prints the value solves the biometric-prompt
problem and leaves the secret in the transcript on every call, which is the more expensive of
the two problems.

## Cleanup

The plugin's `op-cache-cleanup.sh` is a `Stop` hook that purges the cache directories when
the session ends, so values don't sit in `/tmp` until reboot.

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

- [claude-secret-guard](https://github.com/asaphe/claude-secret-guard) — the wrapper, the cleanup hook, and the `PreToolUse` guard that blocks a raw `op read` in the first place
- [`../RETIRED.md`](../RETIRED.md) — where the rest of the retired examples went
