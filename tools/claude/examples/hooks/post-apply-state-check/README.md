# Post-Apply State Check

A **PostToolUse** hook that fires after a *successful* `terraform apply` or `kubectl apply` and reminds the model that exit code 0 proves syntax was accepted — not that the resource is live, healthy, and reachable by its consumers.

## Why This Exists

The recurring failure mode after an apply: the model sees `Apply complete!` or `deployment.apps/foo configured` and declares the task done. But:

- **Terraform** `Apply complete!` proves Terraform's view of the world converged. It does not prove the IAM role's trust policy actually permits the consumer, the SSM parameter is readable from the consumer's role, or the resource behaves as intended.
- **kubectl** `configured`/`created` means the API server accepted the manifest. The pod can still be CrashLoopBackOff, unschedulable, or failing probes ten seconds later.

The verification step is cheap (`aws iam get-role`, `kubectl describe`) and catches the gap between "command succeeded" and "system is correct". This hook makes that step a deterministic nudge instead of an advisory rule the model forgets under context pressure.

## Behavior

| Command result | Action |
|----------------|--------|
| `terraform apply` → `Apply complete!` / `No changes` | Inject post-apply verification checklist |
| `terraform apply` → errored | Silent (a nudge after a failed apply is noise) |
| `kubectl apply` → `configured`/`created`/`unchanged` | Inject `kubectl get`/`describe` verification commands, naming the first applied resource when parseable |
| `kubectl apply` → errored | Silent |
| Anything else | Silent |

- **Exit 0 always** — never blocks, only reminds
- On a match, emits `hookSpecificOutput.additionalContext` JSON on stdout, which Claude Code injects as model-facing context

## Installation

Register as a PostToolUse hook on `Bash`:

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "/path/to/post-apply-state-check.sh"
          }
        ]
      }
    ]
  }
}
```

Requires `jq` on PATH.

## Customization

**Kube context:** the suggested `kubectl` verification commands include `--context ${KUBE_DEFAULT_CONTEXT}`. Set that env var to your cluster context (it pairs naturally with the [kubectl-context-inject](../kubectl-context-inject/) hook's default); unset, the commands show a `<cluster-context>` placeholder.

**Cloud provider:** the Terraform checklist suggests AWS verification commands (`aws iam get-role`, `aws ssm get-parameter`). Swap for your provider's describe/get equivalents.

**More appliers:** the same pattern extends to `helm upgrade` (verify with `helm status` + rollout), `gcloud deploy`, `az deployment` — add a branch per tool, gated on the tool's own success marker in stdout.

## Relationship to Other Hooks

| Hook | Event | Purpose |
|------|-------|---------|
| [**stateful-op-reminder**](../stateful-op-reminder/) | PreToolUse | Before the mutation: follow the Stateful Operations Protocol |
| **post-apply-state-check** | PostToolUse | After the mutation: verify live state, not just exit code |
| [**post-push-hygiene**](../post-push-hygiene/) | PostToolUse | After `git push`: resolve threads, update PR body/tracker |

The pre/post pair brackets every apply: the reminder sets up the baseline-capture discipline before, this hook enforces the verify-after step.
