# iterm2-session

`SessionStart` and `SessionEnd` hooks that set the iTerm2 tab color and title when a Claude Code session starts, and reset them on exit.

## What it does

**On start:** sets the tab chrome color and title based on the current repo and branch.

**On end:** resets the tab color to the default and clears the title.

The result: active Claude sessions have a distinct colored tab; idle tabs return to normal. When multiple Claude windows are open across different repos or branches, each gets a different color — no configuration needed.

## Color derivation

Color is computed from `repo:branch` via `cksum` → 0–359 hue → fully saturated RGB (color wheel). The mapping is:

- **Deterministic** — same repo+branch always produces the same color, across sessions and machines
- **No hardcoded map** — works for any repo, any user, including worktrees in `/tmp/`
- **Distinct** — nearby hues map to visually different colors

```bash
SEED="${REPO}:${BRANCH:-main}"
HASH=$(printf '%s' "$SEED" | cksum | awk '{print $1}')
HUE=$(( HASH % 360 ))
# HUE → sector + fraction → RGB (6-sector color wheel)
```

## Tab title

- On a feature branch: `[repo] branch-name`
- On main/master: `[repo] ~/path/to/project`

## Configuration

```jsonc
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "",
        "hooks": [
          { "type": "command", "command": "/absolute/path/to/iterm2-session-start.sh" }
        ]
      }
    ],
    "SessionEnd": [
      {
        "matcher": "",
        "hooks": [
          { "type": "command", "command": "/absolute/path/to/iterm2-session-end.sh" }
        ]
      }
    ]
  }
}
```

## How it works

iTerm2 supports OSC escape sequences that control the tab chrome color and title. The critical detail: hooks run in a captured stdout context inside Claude Code, so escape sequences written to stdout never reach the terminal. The scripts write directly to `/dev/tty` to bypass this:

```bash
printf '\033]6;1;bg;red;brightness;%d\a' "$R" > /dev/tty
```

Three separate writes set the red, green, and blue brightness values (0–255 each). The `\a` (BEL) terminates each sequence.

## Requirements

- iTerm2 (macOS) — the OSC 6 sequences are iTerm2-specific
- Does nothing and exits 0 on non-iTerm2 terminals (`2>/dev/null` suppresses errors)
