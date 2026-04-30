# model-recommendation

UserPromptSubmit hook that warns when the current model doesn't match the recommended model for the task type. Advisory only — never blocks.

## Why this exists

A common quality / cost mistake: running deep review or security analysis on Sonnet (misses nuance) or running sprint-status / Q&A lookups on Opus (wastes session budget). This hook nudges the user to switch when there's a clear mismatch — the model can also see the suggestion and proactively flag it.

## How it works

1. Reads the user's prompt from the UserPromptSubmit hook payload
2. Reads the transcript JSONL (`transcript_path` from payload), greps the last 200 lines for `"model":"..."`, and normalizes to `opus` / `sonnet` / `haiku`
3. Walks `model-recommendation.json` `.phases[]` in order, matching the prompt against each `pattern` (case-insensitive `grep -qiE`)
4. If a phase matches and the recommended model differs from the current model, emits an `additionalContext` line via `hookSpecificOutput`

## Configuration

`model-recommendation.json` is a list of phases, each with:

- `pattern` — POSIX-ERE regex matched against the user prompt (case-insensitive)
- `model` — recommended model: `opus`, `sonnet`, or `haiku`
- `note` — short rationale shown in the warning

First match wins. Add or reorder phases as your task taxonomy evolves.

The shipped config has two phases:

- Deep work (PR review, security audit, cross-repo audit, architecture review, threat modeling) → Opus
- Q&A and lookups (sprint status, ticket updates, what / how / explain prompts) → Sonnet

## Install

```jsonc
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          { "type": "command", "command": "/absolute/path/to/model-recommendation.sh" }
        ]
      }
    ]
  }
}
```

## Exit codes

| Exit | Meaning |
|------|---------|
| 0 | Always — advisory only. Emits `additionalContext` JSON when a mismatch is detected. |

## Limitations

- Detects model from the transcript's last assistant turn — on the very first turn of a fresh session there's no model to compare against, so no warning fires.
- Pattern-matching is keyword-based, not semantic. A prompt like "review this PR's security architecture" matches both phases — first match (Opus) wins, which is correct, but contrived edge cases can mis-recommend.
