# kubectl Context Inject

A **PreToolUse** hook that auto-injects `--context` into kubectl and helm commands when none is specified.

## Why

If you work with a single Kubernetes cluster (or have a known default), every kubectl/helm command needs `--context my-cluster`. The agent adds this flag to every command, wasting tokens and risking mistakes if it's forgotten.

This hook rewrites commands transparently — `kubectl get pods` becomes `kubectl --context my-cluster get pods`.

## Behavior

| Command | Action |
|---------|--------|
| `kubectl get pods` | Rewrite to `kubectl --context my-cluster get pods` |
| `kubectl --context other get pods` | Allow (already has context) |
| `kubectl config get-contexts` | Allow (config management, skip) |
| `helm repo add ...` | Allow (doesn't target a cluster) |
| `helm upgrade ...` | Rewrite to `helm --context my-cluster upgrade ...` |

Uses `updatedInput` to rewrite the command — the agent sees the rewritten version in the tool result.

## Setup

1. Edit the script: change `DEFAULT_CONTEXT="my-cluster"` to your cluster name
2. Register as a PreToolUse hook on `Bash`:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "/path/to/kubectl-context-inject.sh"
          }
        ]
      }
    ]
  }
}
```

## Customization

**Multi-cluster with a default:** Keep this hook for the default cluster. When the agent needs a different cluster, it specifies `--context` explicitly (which the hook preserves).

**Context from env var:** Replace the hardcoded default with:

```bash
DEFAULT_CONTEXT="${KUBE_DEFAULT_CONTEXT:-my-cluster}"
```

## POSIX Compatibility Note

The `grep -qE` patterns use POSIX Extended Regular Expressions, not PCRE. This matters on macOS where `grep -E` doesn't support `\s`, `\d`, or `\b`. The script uses literal spaces and `[= ]` instead.
