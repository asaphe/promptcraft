# Destructive Operation Guard

PreToolUse hook with two-tier blocking for destructive operations.

## Two-Tier Design

| Tier | Mechanism | Override by `Bash(*)`? | Use for |
|------|-----------|------------------------|---------|
| **Hard block** | `exit 2` + stderr | No — always blocks | Irreversible data loss (AWS deletions, push to main) |
| **Soft block** | JSON `permissionDecision` + `exit 0` | Yes — user can approve | Risky but approvable (PR ops, force-push, terraform destroy) |

Hard blocks stop the tool call unconditionally — no override is possible. The user must run the command themselves in their terminal.

Soft blocks surface a warning. With `Bash(*)` in the allow list, the user sees the warning and can approve in the permission prompt.

## What It Blocks

### Hard Blocks (irreversible)

| Pattern | Why |
|---------|-----|
| `git push` to main/master | Must go through PRs |
| `git push --force` to main/master | Rewrites shared history on default branch |
| `git reset --hard` | Permanent loss of uncommitted work |
| `aws * delete-*`, `aws s3 rm`, `aws ec2 terminate-*` | Cloud resource destruction |

### Soft Blocks (confirm first)

| Pattern | Why |
|---------|-----|
| `gh pr create/merge` | Visible shared actions |
| `gh pr close` | Loses PR context — verify reason and check for unmerged work |
| `git push --force` | History rewriting (reversible via reflog) |
| `git branch -D`, `git checkout --`, `git restore` | Discards local changes |
| `terraform destroy/state rm/force-unlock` | Infrastructure changes |
| `kubectl delete/drain/scale/patch` | Live cluster mutations |
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

# Move git reset --hard to soft block (user can approve)
SOFT_REASON="git reset --hard — discards uncommitted changes (recoverable via reflog)."
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

A single `exit 2` for everything is too strict — it blocks operations the user explicitly asked for (like creating a PR) with no way to approve. A single JSON block is too weak — `Bash(*)` wildcards silently override it for operations that should never be auto-approved (like deleting an RDS instance).

The two-tier approach gives you both: unconditional safety for irreversible operations, and a confirmation prompt for everything else.

## Companion Hooks

- **[`stateful-op-reminder`](../stateful-op-reminder/)** — Nudges (does not block) when detecting mutations to external systems. Catches plausible-looking API calls that destructive-guard can't pattern-match.
- **[`pr-create-guard`](../pr-create-guard/)** — Verifies pre-creation conditions before allowing `gh pr create`.
