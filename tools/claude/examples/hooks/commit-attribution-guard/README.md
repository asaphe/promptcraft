# commit-attribution-guard

Hard-blocks commits that contain AI attribution markers, and branch operations that use the `claude/` namespace.

## Why this exists

Claude Code's `CLAUDE_CODE_UNDERCOVER=1` env var suppresses the automatic `Co-Authored-By: Claude` trailer. It does NOT prevent the model from typing attribution into a heredoc commit message — and the model frequently does so on its own initiative when a CLAUDE.md rule against attribution exists. This hook is the belt-and-suspenders enforcement.

Similarly, Claude Code's autonomous mode defaults to creating branches named `claude/<short-description>`. A CLAUDE.md rule forbidding this isn't enough; the model regresses across sessions. This hook hard-blocks any `git checkout/switch/branch/push` referencing a `claude/`-prefixed branch.

## What it catches

- `Co-Authored-By: Claude` / `Co-Authored-By: Anthropic` in `-m`, `-F`, or heredoc bodies
- `Generated with Claude Code` / `Generated with [Claude Code]` markers
- `claude.ai/code` URLs in commit messages
- 🤖 Generated-by markers
- Branch operations referencing `claude/<anything>`

The flag-permissive pattern `git[[:space:]]([^|;&]* )?commit` catches all forms including `git -C dir commit`, `git --no-pager commit`, and `git --git-dir=foo commit`.

## Configuration

Add to `.claude/settings.json`:

```jsonc
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": "/absolute/path/to/commit-attribution-guard.sh" }
        ]
      }
    ]
  }
}
```

The hook sources `../_lib/hook-diag.sh` (optional — silently skipped if absent) and `../_lib/strip-cmd.sh` (required for the `claude/` branch check). Install both under the same parent directory as the hook.

## Exit codes

| Exit | Meaning |
|------|---------|
| 0 | Allow |
| 2 | Hard block — message printed to stderr |

The hook does not soft-block (exit 1) — these patterns are unambiguous violations of the no-attribution / no-`claude/`-prefix rules.
