# Post-Compact State Injection

Injects live git state into Claude's context after compaction — only the dynamic state that compaction loses and that always-loaded config can't restore.

## Problem

Context compaction compresses prior messages but preserves always-loaded files (CLAUDE.md, `.claude/rules/`). Behavioral rules survive compaction. What doesn't survive is **dynamic git state** established during the session: uncommitted changes, active worktrees, and stashed work. Losing this silently can cause Claude to overwrite in-flight work or forget about parallel worktrees.

## What it injects

- **Uncommitted changes** — `git status --short` (capped at 20 lines)
- **Active worktrees** — other worktrees beyond the main working directory
- **Stash count** — number of stashed changesets

When the working tree is clean with no worktrees or stashes, the hook outputs **nothing** — zero wasted tokens.

## What it does NOT inject (and why)

- **Behavioral rules** — already in always-loaded `.claude/rules/` and `CLAUDE.md`
- **Branch name alone** — existing rules instruct Claude to re-verify state after compaction
- **PR info** — Claude can query with `gh`; rules already instruct re-verification

## Why SessionStart, not PostCompact?

`PostCompact` is **side-effects-only** — it can run scripts but cannot inject content into Claude's context. `SessionStart` with `matcher: "compact"` fires after compaction and adds stdout directly to the context window.

| Hook | Context injection? | Output format |
|------|-------------------|---------------|
| `PostCompact` | No | Side-effects only |
| `SessionStart` (compact) | Yes | Plain text stdout |

## Layer

**Global** (`~/.claude/settings.json`) — applies across all projects.

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

## Example output

```
Post-compaction state:
- Branch: dev-1234-feature
- Uncommitted changes:
 M src/main.py
 M tests/test_main.py
?? tmp/scratch.py
- Active worktrees:
/tmp/repo-hotfix  abc1234 [dev-5678-hotfix]
- Stashed changes: 1
```
