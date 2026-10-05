# Settings Link Check

A **SessionStart** hook that warns when the live `~/.claude/settings.json` has stopped being a symlink to the copy you track in version control.

## Why This Exists

Keeping `settings.json` in a dotfiles repo and symlinking it into `~/.claude/` only works while the link holds. Some tools replace a symlink with a regular file when they rewrite it. After that, every edit to the tracked copy is invisible to Claude Code, and every setting changed in the live file is invisible to version control. Nothing errors; the two files just drift apart.

This hook checks the link at session start and, when it is broken, tells both you and the model what is wrong and how to repair it.

## Behavior

- **Exit 0 always** — never blocks
- Silent when the live file is a symlink resolving to the tracked file
- Otherwise reports the state (tracked file missing, live file missing, a symlink pointing elsewhere, or a regular file with its last-written time), plus a summary of what differs: hook groups and top-level settings present in only one of the two files
- Emits `systemMessage` (shown to the user) and `hookSpecificOutput.additionalContext` (model-facing) as JSON; falls back to plain stdout context when `jq` is missing
- The fix is a manual one: back up the live file, copy its live-only entries into the tracked copy, then `ln -sfn <tracked> <live>`

## Configuration

| Variable | Default | Meaning |
|----------|---------|---------|
| `SETTINGS_LINK_LIVE` | `$HOME/.claude/settings.json` | The file Claude Code reads |
| `SETTINGS_LINK_TRACKED` | `$HOME/dotfiles/claude/settings.json` | The version-controlled copy it should link to |

## Installation

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "\"$HOME/.claude/hooks/settings-link-check/settings-link-check.sh\""
          }
        ]
      }
    ]
  }
}
```

Requires `bash` and `python3`; `jq` is optional (without it the warning is plain stdout context).
