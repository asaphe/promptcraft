# Destructive Operation Guard

PreToolUse hook that hard-blocks destructive git and GitHub CLI operations, forcing Claude to ask the user before proceeding.

## What It Blocks

| Command Pattern | Why |
| --------------- | --- |
| `gh pr close` | Closes a PR — loses review threads, CI history, linked tickets |
| `gh pr merge` | Merges a PR — visible shared action that needs explicit approval |
| `gh pr create` | Creates a PR — visible shared action that needs explicit approval |
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

When Claude attempts a blocked command, the hook writes the reason to stderr and exits with code 2. Exit code 2 is a **hard block** — it stops the tool call before permission rules are evaluated, meaning it works even when `Bash(*)` is in the allow list.

The hook does not prevent the user from running these commands directly in their terminal. It only gates Claude's autonomous execution.

## Exit Code 2 vs JSON permissionDecision

There are two ways to block a tool call from a PreToolUse hook:

| Method | Mechanism | Override by `Bash(*)` allow? |
|--------|-----------|------------------------------|
| `exit 2` + stderr message | **Hard block** — stops before permission evaluation | No — always blocks |
| JSON `permissionDecision: "block"` + `exit 0` | **Soft block** — evaluated alongside permissions | Yes — `Bash(*)` overrides it |

**Always use exit code 2 for safety guardrails.** The JSON approach is only appropriate for advisory signals where you want the allow list to have the final say.

This distinction matters because many setups use `Bash(*)` for frictionless operation. Without exit code 2, the destructive guard becomes a no-op — commands execute without any prompt.

## Customization

Add patterns for your stack. Common additions:

```bash
# Terraform destroy
if echo "$CMD" | grep -qE 'terraform\s+destroy'; then
  REASON="terraform destroy — destroys infrastructure. Confirm target workspace and resources first."
fi

# Terraform state removal
if echo "$CMD" | grep -qE 'terraform\s+state\s+rm'; then
  REASON="terraform state rm — removes resources from state, orphaning them."
fi

# kubectl delete
if echo "$CMD" | grep -qE 'kubectl\s+delete\s'; then
  REASON="kubectl delete — permanently removes Kubernetes resources."
fi

# AWS resource deletion
if echo "$CMD" | grep -qE 'aws\s+\S+\s+delete-'; then
  REASON="AWS delete operation — confirm the target resource before proceeding."
fi
```

## Relationship to Rules

This hook enforces behavior that CLAUDE.md rules describe. Rules say "ask before destructive operations" — this hook ensures it happens even when Claude forgets. Both are needed: rules for understanding, hooks for enforcement.
