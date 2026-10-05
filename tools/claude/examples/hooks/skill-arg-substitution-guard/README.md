# Skill Arg Substitution Guard

A **PreToolUse** hook on `Edit`, `MultiEdit` and `Write` that blocks writing a `$<digits>` token into a `SKILL.md` or a `commands/*.md` file.

## Why This Exists

When a skill or slash command runs with arguments, Claude Code replaces `$0`, `$1` and so on in its markdown with the argument at that 0-based index; a placeholder with no matching argument stays as written. An awk field (`awk '{print $1}'`) or a price in prose (`costs $5.`) is therefore rewritten silently, and the skill misbehaves only when it is invoked with enough arguments to reach that index, far from the edit that caused it. The documented escape is a single backslash (`\$1`); a doubled one (`\\$1`) still expands.

The match rule this hook uses, `\$\d+(?!\w)` (a dollar sign, digits, then anything that is not a word character), was read from the Claude Code binary and is not documented. The documented behavior is in [Available string substitutions](https://code.claude.com/docs/en/skills#available-string-substitutions).

This hook catches the token at write time, when the fix is a one-line edit.

## Behavior

| Edited file | New text | Action |
|-------------|----------|--------|
| Not `*/SKILL.md` or `*/commands/*.md` | any | Allow |
| A skill or command file | No `$<digits>` token, or only escaped ones (`\$1`) | Allow |
| A skill or command file | `$<digits>` followed by a non-word character | Block (exit 2) with the first matching lines |
| A skill or command file | New text cannot be read from the payload | Block (exit 2): fail closed rather than pass an unchecked edit |

- Only the new text is checked (`content`, `new_string`, or every `edits[].new_string`), so deleting an existing token is never blocked
- `$ARGUMENTS` and `$ARGUMENTS[N]` are intended substitutions and are allowed
- The block message names the safe spellings: the documented `\$N` escape, awk fields as `$(N)`, shell positionals as `${N}`, and prose without the `$`

## Installation

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Edit|MultiEdit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "\"$HOME/.claude/hooks/skill-arg-substitution-guard/skill-arg-substitution-guard.sh\""
          }
        ]
      }
    ]
  }
}
```

Requires `jq` and `perl` on PATH. Optionally sources `../_lib/hook-diag.sh` (see [`_lib/`](../_lib/)) so block reasons are re-emitted from stderr.
