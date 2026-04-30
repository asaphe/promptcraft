# `_lib/` — shared utilities for hook authors

This directory holds shell utilities that other hooks source. The leading underscore signals "infrastructure, not a hook itself" — the loader doesn't try to register `_lib/*.sh` as hooks.

## What's here

| File | Purpose |
|------|---------|
| [`strip-cmd.sh`](strip-cmd.sh) | `strip_cmd "$CMD"` returns `$CMD` with heredoc bodies and `-m`/`--message` argument contents replaced by placeholders, so downstream pattern matching doesn't false-positive on commit-message text. |
| [`hook-diag.sh`](hook-diag.sh) | Diagnostic wrapper. Sourced AFTER reading stdin into `$INPUT`. Logs hook name, exit code, command, and stderr tail to a rotating log. Re-emits captured stderr to Claude Code on exit 1 (soft block) and exit 2 (hard block) so the block reason is visible to the model. |

## Why these exist

### `strip-cmd.sh`

`grep -qE 'gh +pr +close'` will hit on a commit message that contains the words "gh pr close" — typically when the model writes a heredoc explaining what NOT to do. `strip_cmd` removes the heredoc body before matching, so guard patterns only fire on the actual command surface.

### `hook-diag.sh`

A common Claude Code hook authoring pitfall: a hook exits 1 or 2 with a `>&2` message, but Claude Code's UI shows "No stderr output" and the model doesn't know why it was blocked. The cause is that Claude Code captures stderr through a pipe, and depending on shell-buffering / FD layout the message can be lost.

`hook-diag.sh` solves this by saving the original stderr to FD 3, redirecting FD 2 to a temp file, and on exit re-emitting the captured content via `exec 2>&3; echo "$captured" >&2`. The model sees the reason; the user sees a clean log at `/tmp/claude-hook-diag.log` for non-zero exits.

## Usage in a hook

```bash
#!/usr/bin/env bash
# my-hook.sh

INPUT=$(cat)                              # MUST be first — hook-diag reads $INPUT
HOOK_DIAG_NAME="my-hook"                  # optional, otherwise uses basename
source "$(dirname "$0")/../_lib/hook-diag.sh"

# ... extract CMD, do work, source strip-cmd if needed:
source "$(dirname "$0")/../_lib/strip-cmd.sh"
CMD_STRIPPED=$(strip_cmd "$CMD")

if echo "$CMD_STRIPPED" | grep -qE '<bad-pattern>'; then
  echo "BLOCKED: <reason>" >&2
  exit 2
fi

exit 0
```

## Common authoring mistake

When using `${HOME}/.claude/hooks/_lib/strip-cmd.sh` style absolute paths in `source`, ALWAYS close the double quote:

```bash
# CORRECT
source "${HOME}/.claude/hooks/_lib/strip-cmd.sh"

# BROKEN — bash treats as multi-line string until next " on a later line.
# `bash -n` won't catch this; the next line gets eaten as part of the
# (malformed) source argument and the function silently fails to load.
source "${HOME}/.claude/hooks/_lib/strip-cmd.sh
CMD_STRIPPED=$(strip_cmd "$CMD")
```

The relative form `source "$(dirname "$0")/../_lib/strip-cmd.sh"` is more portable across install locations and is the recommended style.
