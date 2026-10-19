# context-budget-stop

A **Stop** hook that, once a session's context passes a budget, holds one turn end so Claude writes a self-contained handoff and asks whether to continue in a fresh session, instead of drifting into compaction.

## Why

Compaction summarises a session at a moment nobody chose, and whatever the summary drops is gone. A handoff written on purpose, just before that point, carries the decisions, the stop point and the open question forward in a file a new session can read. Starting fresh from it also costs far less per turn than carrying a near-full context.

A per-prompt nudge ("context is large, consider `/clear`") is the obvious alternative and the weaker one: it arrives at the start of a turn, when the model is about to act on the user's message, and gets read past. A Stop block lands at a turn boundary, where writing a handoff is the natural next step.

## How it works

The work is split between two scripts so that the hook on every turn end does almost nothing.

- **Detect, in the statusline.** The [statusline](../statusline/) already receives `context_window.used_percentage` and `context_window.context_window_size` on every refresh. When their product reaches the budget, it writes a flag file named after the session (`<tokens> <budget>`), posts one desktop notification, and turns the `ctx:` segment red. No transcript parsing, no extra per-prompt hook.
- **Act, in the Stop hook.** `context-budget-stop.sh` checks for that flag with shell builtins. On the first turn end that finds it, it claims a `.handled` marker and blocks the yield with a reason telling Claude not to start a new step or `/compact`, to write the handoff (objective, verified state, decisions, remaining work, evidence and file paths, approval limits, stop point, pending question) to a file outside the repository, to ask whether to continue in a fresh session, and to end with `read <path> and continue`.
- **Once per session.** The `.handled` marker is created with `noclobber`, so it is atomic: a declined handoff never re-prompts, and two racing turn ends cannot both block. When another Stop hook has already blocked this yield (`stop_hook_active: true`), the hook defers to the next turn end without consuming the flag, rather than chaining onto that block.
- **Backstop.** Native auto-compaction stays on. This hook only gets in first.

## Budget

| Variable | Default | Effect |
|---|---|---|
| `CLAUDE_CONTEXT_BUDGET_TOKENS` | unset | An absolute budget in tokens. It can only lower the budget, never raise it past the ceiling below. Non-numeric or zero values are ignored |
| `CLAUDE_CONTEXT_BUDGET_DIR` | `~/.claude/context-budget` | Where flags and `.handled` markers live. Both scripts read the same variable |

The budget is three quarters of the model's context window, or `CLAUDE_CONTEXT_BUDGET_TOKENS` if that is lower. The ceiling exists so a small window still flags with room left to write the handoff before auto-compaction. On a 200k window the default is 150k; on a 1M window, 750k, and `CLAUDE_CONTEXT_BUDGET_TOKENS=500000` moves it to 500k.

The statusline reads both variables, so they must be in the environment Claude Code starts with: export them from your shell profile, or set them under `env` in `settings.json`.

## Setup

Install both scripts and register the Stop entry alongside the statusline in `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "$HOME/.claude/hooks/statusline/statusline-command.sh"
  },
  "hooks": {
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.claude/hooks/context-budget-stop/context-budget-stop.sh",
            "timeout": 30
          }
        ]
      }
    ]
  }
}
```

Without the statusline nothing writes a flag, so the hook allows every turn end. If you use your own statusline, port the block marked `context-budget-stop` in [`statusline-command.sh`](../statusline/statusline-command.sh): it needs `session_id` and `context_window.context_window_size` from the statusline input.

Requires `bash`, `awk` and `jq` (the statusline already uses them). The Stop hook itself uses only shell builtins. Notifications use `osascript` on macOS or `notify-send` on Linux when present, and are skipped otherwise.

## Output contract

Exit 0 with no output to allow. To block, exit 0 with `{"decision":"block","reason":"…"}` on stdout. The reason is fixed text with integer substitutions only, so the hook emits it with `printf` and needs no JSON escaping.

Every unusable input allows: no stdin, malformed JSON, a missing session ID, or one outside `[A-Za-z0-9_-]` (which also keeps a crafted ID from reaching a path outside the flag directory). A flag whose contents are unreadable still blocks once, reporting `~0k`.

## Housekeeping

Each session that crosses its budget leaves two small files in `CLAUDE_CONTEXT_BUDGET_DIR`. Nothing deletes them automatically, because a sweep inside a statusline that honours a user-set directory could delete files that are not its own. Clear them when convenient:

```bash
find "${CLAUDE_CONTEXT_BUDGET_DIR:-$HOME/.claude/context-budget}" -type f -mtime +7 -delete
```

Deleting a live session's flag and marker re-arms it: the statusline re-flags it on the next refresh and the hook blocks once more.

## Tests

[`hook-tests/test-context-budget.py`](../../hook-tests/test-context-budget.py) runs the statusline and the hook together against a temporary flag directory with the notifiers stubbed: default and capped budgets, one notification per session, block once then allow, the `stop_hook_active` deferral, unusable inputs, and the Stop output contract.
