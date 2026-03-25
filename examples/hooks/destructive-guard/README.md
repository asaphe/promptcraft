# Destructive Operation Guard

PreToolUse hook with two-tier blocking for destructive operations.

## Two-Tier Design

| Tier | Mechanism | Override by `Bash(*)`? | Use for |
|------|-----------|------------------------|---------|
| **Hard block** | `exit 2` + stderr | No — always blocks | Irreversible data loss (AWS deletions, `git reset --hard`) |
| **Soft block** | JSON `permissionDecision` + `exit 0` | Yes — user can approve | Risky but approvable (PR ops, force-push, terraform destroy) |

Hard blocks stop the tool call before permission rules are evaluated — the user must run the command themselves or explicitly instruct Claude to proceed after seeing the block message.

Soft blocks surface a warning. With `Bash(*)` in the allow list, the user sees the warning and can approve in the permission prompt.

## What It Blocks

### Hard Blocks (irreversible)

| Pattern | Why |
|---------|-----|
| `git push` on main/master | Must go through PRs |
| `git reset --hard` | Permanent loss of uncommitted work |
| `aws * delete-*`, `aws s3 rm`, `aws ec2 terminate-*` | Cloud resource destruction |

### Soft Blocks (confirm first)

| Pattern | Why |
|---------|-----|
| `gh pr create/close/merge` | Visible shared actions |
| `git push --force` | History rewriting (reversible via reflog) |
| `git branch -D`, `git checkout --`, `git restore` | Discards local changes |
| `terraform destroy/state rm/force-unlock` | Infrastructure changes |
| `kubectl delete/drain/scale/patch` | Live cluster mutations |
| `helm uninstall/rollback` | Release changes |

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

# Move gh pr close to soft block (user can approve)
SOFT_REASON="gh pr close — confirm with user first."
```

Add patterns for your stack:

```bash
# Docker — soft block
if echo "$CMD" | grep -qE 'docker\s+(rm|rmi|system\s+prune)'; then
  SOFT_REASON="docker cleanup — removes containers or images."
fi

# Database CLI — hard block
if echo "$CMD" | grep -qE '(psql|mysql|mongo).*DROP\s+(DATABASE|TABLE)'; then
  HARD_REASON="database DROP — irreversible schema destruction."
fi
```

## Why Two Tiers?

A single `exit 2` for everything is too strict — it blocks operations the user explicitly asked for (like creating a PR) with no way to approve. A single JSON block is too weak — `Bash(*)` wildcards silently override it for operations that should never be auto-approved (like deleting an RDS instance).

The two-tier approach gives you both: unconditional safety for irreversible operations, and a confirmation prompt for everything else.
