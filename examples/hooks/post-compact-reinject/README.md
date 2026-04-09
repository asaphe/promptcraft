# Post-Compact Context Re-injection

Re-injects critical context into Claude's conversation after context compaction.

## Problem

When Claude Code compacts context (automatically or via `/compact`), behavioral rules, branch state, and active PR info can be lost. This causes Claude to forget project conventions, lose track of in-progress work, or drift from established patterns.

## Solution

A `SessionStart` hook with `matcher: "compact"` that outputs plain text to stdout. Claude Code adds this stdout directly to Claude's context window after compaction completes.

## Why SessionStart, not PostCompact?

`PostCompact` is a **side-effects-only** event. It can run scripts (logging, cleanup) but has no mechanism to inject content into Claude's context. The correct hook type for context injection after compaction is `SessionStart` with `matcher: "compact"`.

| Hook | Context injection? | Output format |
|------|-------------------|---------------|
| `PostCompact` | No | Side-effects only |
| `SessionStart` (compact) | Yes | Plain text stdout |

## What it injects

- Current git branch
- Active PR number, state, and review status (if on a feature branch with `gh` available)
- Key behavioral rules that tend to get lost during compaction

## Layer

**Global** (`~/.claude/settings.json`) — Personal behavioral rules, applies across all projects.

## Settings configuration

```json
{
  "hooks": {
    "SessionStart": [{
      "matcher": "compact",
      "hooks": [{
        "type": "command",
        "command": "/path/to/post-compact-reinject.sh"
      }]
    }]
  }
}
```

## Customization

Edit the final `echo` line in the script to include your project-specific rules. Focus on rules that:

- Are frequently violated after compaction
- Affect safety (destructive operation guards, review standards)
- Are non-obvious (conventions that can't be inferred from the codebase)

Keep the output concise — every line consumes context window tokens on every compaction.
