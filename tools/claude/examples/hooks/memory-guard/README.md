# Memory Guard

A **PreToolUse** hook that blocks writes to project memory for repos with multiple clones or worktrees.

## Why

Claude Code's project memory is stored at `~/.claude/projects/<path-hash>/memory/`. The path hash is derived from the **filesystem path** of the project, not the git remote or repo name. This means:

- Memory written in `~/projects/myrepo` loads only when working in `~/projects/myrepo`
- Memory written in `~/projects/myrepo-2` loads only when working in `~/projects/myrepo-2`
- Memory written in a git worktree at `~/worktrees/feature-a` loads only in that worktree

If you have multiple clones of the same repo (common for parallel work), project memory becomes unreliable — you write a learning in one clone, but it never surfaces in the others.

## Alternatives to Project Memory

| Storage | Scope | When to Use |
|---------|-------|-------------|
| Global `~/.claude/CLAUDE.md` | All projects | Behavioral preferences, cross-project rules |
| `.claude/rules/` (committed) | All clones of this repo | Team-wide patterns, repo-specific standards |
| `.claude/docs/` (committed) | All clones of this repo | On-demand reference docs |
| Global `~/.claude/docs/` | All projects | Personal reference docs |

## Setup

Register as a PreToolUse hook on `Write` in `~/.claude/settings.json`:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Write",
        "hooks": [
          {
            "type": "command",
            "command": "/path/to/memory-guard.sh"
          }
        ]
      }
    ]
  }
}
```

## Customization

The script has three options for matching which repos to guard. Edit the script to choose your approach:

**Option A: Match a naming pattern** — Guard only repos whose path matches a specific clone naming convention (e.g., `myproject-2`, `myproject-3`).

**Option B: Match a parent directory** — Guard all repos under a known directory that contains clones.

**Option C: Always block** (default) — The safest option. Block all project memory writes and force use of global memory or committed `.claude/rules/`.

## Hard Block

This hook uses `exit 2` (hard block) because writing to the wrong memory location is a silent failure — the data appears saved but never loads in other clones. The user gets no indication that their "remembered" knowledge is invisible in 6 out of 7 clones.
