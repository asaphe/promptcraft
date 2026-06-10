# Intent Router

A **UserPromptSubmit** hook that pattern-matches short free-text prompts ("merged", "status?", "comments?", "review", "finalize", "done?") and injects context that routes the assistant to the matching skill or required follow-up action.

## Why This Exists

Session history shows users typing the same short phrases over and over without invoking a slash command. The assistant has to re-derive intent each time — and frequently improvises a manual path (raw `gh api` calls, ad-hoc checklists) instead of the codified skill that encapsulates the team's discipline. The manual path drifts: bot comments get misattributed, pre-merge gates get skipped, the tracker doesn't get updated.

This hook closes the gap deterministically: when a prompt matches a high-confidence trigger, the model receives injected context naming the skill it must call (or the enumeration it must perform) before answering.

## What It Routes

| Intent | Trigger examples | Routed to |
|--------|-----------------|-----------|
| User-initiated merge | "merged", "i merged", "pr merged" | Confirm PR + ticket, update tracker, surface queue |
| Status probe | "status?", "any updates?", "where are we" | Enumerate ALL in-flight state, report concretely |
| Comment sweep | "comments?", "check for comments", "resolve feedback" | [`pr-check`](../../skills/pr-check.md) skill |
| PR review | "review the pr", "run the review" | [`pr-review`](../../skills/pr-review.md) skill |
| Finalize | "finalize", "ready to merge?", "pre-merge" | [`pr-finalize`](../../skills/pr-finalize.md) skill |
| Session queue | "done?", "what's left", "anything else?" | Enumerate PRs/tickets/deferred items, then propose |
| Link request | "links?", "link to the pr", "url" | `gh pr view --json url,number,title` |

## Design Rules

- **High precision over recall.** False positives are worse than misses — they nudge the assistant in the wrong direction. Patterns require the prompt to be short (≤ 200 chars) AND anchored to a well-known trigger phrase. Long free-form prompts are skipped entirely.
- **The hook never invokes a skill itself.** It only injects context naming the required next tool call. The assistant decides whether to call `Skill(...)` — this preserves the answer-before-acting contract for ambiguous cases, via the built-in escape hatch: if the user's ask reads materially narrower than the skill scope, the injected context tells the model to surface the mismatch in one line and act on the answer.
- **No per-session stamp.** Each occurrence injects context — the user is signaling intent every time they type the phrase.
- Slash commands (`/...`) are skipped — they're already routed by the slash handler.

## Behavior

- **Exit 0 always** — never blocks
- On a match, emits `hookSpecificOutput.additionalContext` JSON on stdout, which Claude Code injects into the conversation as model-facing context
- On no match, emits nothing

## Installation

Register as a UserPromptSubmit hook:

```json
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "/path/to/intent-router.sh"
          }
        ]
      }
    ]
  }
}
```

Requires `jq` on PATH.

## Customization

The skill names in the injected context map to the skills shipped in this repo ([`pr-check`](../../skills/pr-check.md), [`pr-review`](../../skills/pr-review.md), [`pr-finalize`](../../skills/pr-finalize.md)). Swap them for your own skill names, and adjust the "update your tracker" language to name your issue tracker's actual update mechanism (MCP tool, CLI, API).

Adding an intent is mechanical: one `grep -qE` anchored pattern + one `CTX` append. Keep patterns anchored (`^...`) and short-prompt-gated — an unanchored pattern like `(review|status)` would fire on substantive prompts that merely mention those words.

## Relationship to Other Hooks

| Hook | Event | Purpose |
|------|-------|---------|
| **intent-router** | UserPromptSubmit | Routes free-text intent to skills/actions |
| [**model-recommendation**](../model-recommendation/) | UserPromptSubmit | Warns on model/task mismatch |
| [**clone-id-inject**](../clone-id-inject/) | UserPromptSubmit | Injects repo clone identity |

All three are advisory injectors — they shape the model's next move without blocking anything.
