# Model/Effort Pin Guard

A **SessionStart** hook that re-pins `model` and `effortLevel` in your user settings, because a `/model` pick persists itself as the new default.

## Why

Picking a model in the `/model` picker saves that model as the default for every later session, and `/effort` persists the level under `modelSettings.<model>.effortLevel`. One experimental switch silently becomes the standing default. This hook compares the settings file against the values you intend at each session start and restores them when they have drifted.

Picks made session-only (`s` in the `/model` picker or `/effort` slider) never reach the settings file, so the hook does not touch them. A top-level `effortLevel` in user settings does not apply to Opus 5.5 and later models, which is why the per-model pins exist.

## What it does

- Reads `model`, `effortLevel` and `modelSettings.<model>.effortLevel` from the settings file
- Exits silently, without rewriting the file, when nothing has drifted
- Otherwise rewrites the file in place (through a symlink, so a dotfiles link survives) and tells Claude what it restored via `additionalContext`
- Does nothing when `jq` or the settings file is missing; it never blocks

## Configuration

| Variable | Default | Meaning |
|----------|---------|---------|
| `PIN_MODEL` | `opus` | Value pinned to `model` |
| `PIN_EFFORT` | `medium` | Value pinned to the top-level `effortLevel` |
| `PIN_MODEL_EFFORTS` | JSON map for `claude-opus-5-5` (`medium`), `claude-fable-5-1` (`high`), `claude-sonnet-5-5` (`medium`) | Per-model `effortLevel` pins; the levels follow the role table in [`multi-model-orchestration.md`](../../docs/multi-model-orchestration.md) |
| `PIN_GUARD_SETTINGS` | `$HOME/.claude/settings.json` | Settings file to guard |

Set the variables in the hook command (`PIN_MODEL=sonnet "$HOME/.claude/hooks/..."`) or edit the defaults at the top of the script.

## Setup

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.claude/hooks/model-effort-pin-guard/model-effort-pin-guard.sh"
          }
        ]
      }
    ]
  }
}
```

## Trade-off

The guard also reverts a deliberate change made through `/model` or `/effort` at the next session start. To change the real default, change the pin, not the picker.
