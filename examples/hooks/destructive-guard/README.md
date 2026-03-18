# Destructive Operation Guard

PreToolUse hook that blocks destructive git and GitHub CLI operations, forcing Claude to ask the user before proceeding.

## What It Blocks

| Command Pattern | Why |
| --------------- | --- |
| `gh pr close` | Closes a PR — loses review threads, CI history, linked tickets |
| `gh pr merge` | Merges a PR — visible shared action that needs explicit approval |
| `gh run delete` | Permanently removes CI run history |
| `git push origin :branch` | Deletes a remote branch, auto-closing any PR using it |
| `git push --force` | Rewrites remote history |
| `git branch -D` | Force-deletes a branch with potentially unmerged work |
| `git reset --hard` | Discards all uncommitted changes |
| `git checkout --` | Discards uncommitted file changes |
| `git restore` (non-staged) | Discards uncommitted file changes |

## Installation

Add to your `settings.json` (user or project level):

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

## How It Works

When Claude attempts a blocked command, the hook returns `permissionDecision: "block"` with a reason explaining what the command does and suggesting an alternative. Claude sees the block message and must adjust its approach — typically by asking the user for confirmation.

The hook does not prevent the user from running these commands directly in their terminal. It only gates Claude's autonomous execution.

## Customization

Add patterns for your stack. Common additions:

```bash
# Terraform destroy
if echo "$CMD" | grep -qE 'terraform\s+destroy'; then
  REASON="terraform destroy — destroys infrastructure. Confirm target workspace and resources first."
fi

# kubectl delete namespace
if echo "$CMD" | grep -qE 'kubectl\s+delete\s+namespace'; then
  REASON="kubectl delete namespace — destroys all resources in the namespace."
fi

# AWS resource deletion
if echo "$CMD" | grep -qE 'aws\s+\S+\s+delete-'; then
  REASON="AWS delete operation — confirm the target resource before proceeding."
fi
```

## Relationship to Rules

This hook enforces behavior that CLAUDE.md rules describe. Rules say "ask before destructive operations" — this hook ensures it happens even when Claude forgets. Both are needed: rules for understanding, hooks for enforcement.
