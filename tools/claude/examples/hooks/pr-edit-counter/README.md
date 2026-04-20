# PR Edit Counter

A **PreToolUse** hook that tracks how many times the PR body is edited in a session and warns after repeated edits.

## Why

AI agents tend to iteratively refine PR descriptions — draft, post, re-read, edit, edit again. Each `gh pr edit --body` rewrites the entire body, consuming API calls and tokens. More importantly, iterative editing suggests the body wasn't fully thought through before posting.

This hook nudges toward "draft once, post once" discipline by warning after the 2nd body edit on the same PR.

## Behavior

| Edit Count | Action |
|-----------|--------|
| 1st-2nd | Allow silently |
| 3rd+ | Allow with warning message injected into context |

The hook **never blocks** — it's advisory only. The warning reminds the agent to draft the full body locally before posting.

## Setup

Register as a PreToolUse hook on `Bash` in `~/.claude/settings.json`:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "/path/to/pr-edit-counter.sh"
          }
        ]
      }
    ]
  }
}
```

## State Management

Uses temp files at `/tmp/claude-pr-edit-count-<PR_NUMBER>` as counters. These are cleaned up by the [session-quality-capture](../session-quality-capture/) Stop hook at session end.

If you don't use the session-quality-capture hook, add cleanup to your own Stop hook or accept that counters reset on reboot (temp files).

## Design Decisions

- **Advisory, not blocking** — Blocking PR edits would be too aggressive. The goal is awareness, not prevention.
- **Threshold of 2** — The first edit is expected (initial post). The second is normal (responding to review). The third suggests a pattern worth surfacing.
- **Per-PR tracking** — Different PRs have independent counters. Editing PR #123 three times triggers the warning; editing #123 once and #456 once does not.
