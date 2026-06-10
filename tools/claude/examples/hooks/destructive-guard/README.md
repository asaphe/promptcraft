# Destructive Operation Guard

PreToolUse hook with two-tier blocking for destructive operations.

## Two-Tier Design

| Tier | Mechanism | Override by `Bash(*)`? | Use for |
|------|-----------|------------------------|---------|
| **Hard block** | `exit 2` + stderr | No — always blocks | Irreversible data loss and forbidden PR ops (AWS deletions, push/force-push to main, PR close/merge) |
| **Soft block** | JSON `permissionDecision: ask` + `exit 0` | Yes — user can approve | Risky but approvable (PR create, force-push to a branch, terraform destroy) |

Hard blocks stop the tool call unconditionally — no override is possible. The user must run the command themselves in their terminal.

Soft blocks emit `permissionDecision: ask` JSON on stdout and exit 0. Claude Code shows the reason in a permission prompt where the user can approve or deny — even when `Bash(*)` is in the allow list.

## What It Blocks

### Hard Blocks (irreversible)

| Pattern | Why |
|---------|-----|
| `git push` to main/master | Must go through PRs |
| `git push --force` to main/master | Rewrites shared history on default branch |
| `gh pr close` | Loses PR context — never without explicit user instruction |
| `gh pr merge` | The user merges PRs themselves |
| `git clean -f` | Permanently deletes untracked files |
| `git stash drop/clear` | Permanently discards stashed changes |
| `aws * delete-*`, `aws s3 rm`, `aws ec2 terminate-*` | Cloud resource destruction |

### Soft Blocks (confirm first)

| Pattern | Why |
|---------|-----|
| `gh pr create` | Visible shared action |
| `gh run delete` | Permanently removes CI run history |
| `git push --force` to a non-default branch | History rewriting (reversible via reflog) |
| `git reset --hard` | Discards uncommitted changes (recoverable via reflog) |
| `git branch -D`, `git checkout --`, `git restore` | Discards local changes |
| `terraform destroy/state rm/force-unlock/workspace delete` | Infrastructure changes |
| `kubectl delete/drain/cordon/scale/rollout undo/patch` | Live cluster mutations |
| `helm uninstall/rollback` | Release changes |

## Worktree-Aware Push Detection

The guard correctly handles worktree-based workflows where the repo root stays on `main`:

- `cd /tmp/worktree && git push origin branch` — detects the `cd` and checks the branch in the target directory, not the hook's CWD
- `git push origin feature-branch` — recognizes a named non-main branch is safe
- `git push origin local:remote` — recognizes explicit refspecs are safe (unless pushing TO main)
- `git push origin feature:main` — correctly blocks pushing to main via refspec

This prevents false positives when the hook's working directory is on `main` but the push targets a feature branch in a worktree.

## Installation

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "/path/to/destructive-guard.sh"
          }
        ]
      }
    ]
  }
}
```

Requires `jq` on PATH.

## Customization

Move patterns between tiers based on your risk tolerance:

```bash
# Move terraform destroy to hard block (no approval possible)
HARD_REASON="terraform destroy — blocked unconditionally."

# Move git stash drop to soft block (user can approve)
SOFT_REASON="git stash drop — permanently discards stashed changes."
```

Add patterns for your stack:

```bash
# Docker — soft block
if echo "$CMD" | grep -qE 'docker +(rm|rmi|system +prune)'; then
  SOFT_REASON="docker cleanup — removes containers or images."
fi

# Database CLI — hard block
if echo "$CMD" | grep -qE '(psql|mysql|mongo).*DROP +(DATABASE|TABLE)'; then
  HARD_REASON="database DROP — irreversible schema destruction."
fi
```

## Why Two Tiers?

A single `exit 2` for everything is too strict — it blocks operations the user explicitly asked for (like creating a PR) with no way to approve. A single `ask` prompt for everything is too weak — one keystroke in the permission prompt approves an operation that should never be approvable mid-session (like deleting an RDS instance).

The two-tier approach gives you both: unconditional safety for irreversible operations, and a confirmation prompt for everything else.

## Companion Hooks

- **[`stateful-op-reminder`](../stateful-op-reminder/)** — Nudges (does not block) when detecting mutations to external systems. Catches plausible-looking API calls that destructive-guard can't pattern-match.
- **[`pr-create-guard`](../pr-create-guard/)** — Verifies pre-creation conditions before allowing `gh pr create`.
