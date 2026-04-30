# Production Safety Protocol — Per-System Checklists

This document provides concrete verification commands for the Stateful Operations Protocol. Use these checklists when modifying external system state in production.

> Post-action checks below use a generic `<obs-cli>` placeholder. Substitute your observability tool's CLI (Datadog `pup`, New Relic CLI, Grafana Cloud CLI, etc.).

## Common Pattern: What Goes Wrong

In every production incident driven by an "obvious-looking" change going wrong, the failure mode is the same:

1. **Acted on assumed state** — derived facts from naming, context, or partial knowledge instead of querying the live system
2. **No baseline captured** — couldn't compare before/after because "before" was never recorded
3. **No post-action verification** — assumed the action worked and moved on
4. **Compounding errors during fix** — rushed to fix, made it worse (e.g., removed permissions from users while trying to restore them)
5. **Admin-only verification** — checked the API/admin view but didn't test from the user's perspective

The protocol exists to break this pattern. Capture state, mutate, verify behavior (not just state), test from the consumer's perspective.

## AWS IAM / SSO

### Pre-Action

```bash
# List current policies/roles attached to the target
aws iam list-attached-role-policies --role-name <ROLE>
aws iam list-role-policies --role-name <ROLE>

# For SSO permission sets (run with the management-account profile)
aws sso-admin list-permission-sets-provisioned-to-account \
  --instance-arn <ARN> --account-id <ACCT>

# Save baseline
aws iam get-role --role-name <ROLE> > /tmp/iam-baseline-$(date +%s).json
```

### Post-Action

```bash
# Compare current state against baseline
aws iam list-attached-role-policies --role-name <ROLE>
# Diff against saved baseline

# Verify a service that depends on this role can still authenticate
# e.g., check pod service account can assume the role:
kubectl exec -it <pod> --context <cluster> -- aws sts get-caller-identity

# Check CloudTrail for unexpected access denials (last 15min)
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=AssumeRole \
  --start-time $(date -u -v-15M +%Y-%m-%dT%H:%M:%SZ) | jq '.Events[] | select(.errorCode != null)'
```

### Key Rules

- Never modify IAM in prod without testing equivalent change in a non-prod account first
- AWS Identity Center permission sets live in the management account — use the appropriate profile
- Check `sts get-caller-identity` after any trust policy change to verify access still works

## Kubernetes / EKS

### Pre-Action (K8s)

```bash
# Capture current state of the resource
kubectl get <resource> <name> -n <ns> --context <cluster> -o yaml > /tmp/k8s-baseline-$(date +%s).yaml

# For deployments — check current replicas, image, env vars
kubectl describe deployment <name> -n <ns> --context <cluster>

# Check pod health before changes
kubectl get pods -n <ns> --context <cluster> -o wide
```

### Post-Action (K8s)

```bash
# Verify rollout completed successfully
kubectl rollout status deployment/<name> -n <ns> --context <cluster> --timeout=120s

# Check pod health after changes
kubectl get pods -n <ns> --context <cluster> -o wide

# Verify the application is responding
kubectl exec -it <pod> -n <ns> --context <cluster> -- curl -s localhost:<port>/health

# Compare against baseline
diff /tmp/k8s-baseline-*.yaml <(kubectl get <resource> <name> -n <ns> --context <cluster> -o yaml)

# Check observability for errors in the last 5 minutes
<obs-cli> logs search "service:<service> status:error" --from 5m  # e.g. Datadog pup, your equivalent
```

### Key Rules (K8s)

- All `kubectl` commands must include `--context <cluster>` — never rely on the default context
- Clusters with private endpoints require an active VPN — timeout means VPN is disconnected, not "cluster down"
- `kubectl apply` is a mutation — verify after, even though it's not in destructive-guard
- Helm upgrade/install: always `--dry-run` first, review the diff

## Terraform

### Pre-Action (Terraform)

```bash
# Always plan before apply
terraform plan -out=tfplan

# Review the plan carefully — count resources to be created/modified/destroyed
terraform show tfplan | grep -E "^(Plan:|  #)"

# For destroy operations — enumerate every resource explicitly
terraform plan -destroy | grep "will be destroyed"
```

### Post-Action (Terraform)

```bash
# Verify state matches reality
terraform plan  # Should show "No changes"

# For infrastructure changes — verify the resource exists and is configured correctly
# Use AWS/K8s CLI to query the actual resource, don't trust Terraform alone

# Check dependent services
<obs-cli> monitors search "<service>"  # e.g. Datadog pup, your equivalent
```

### Key Rules (Terraform)

- Never destroy more than one workspace at a time without per-resource confirmation
- `terraform plan` shows intent, not result — always verify the actual resource after apply
- Secret paths: verify the path resolves to the correct environment (stg vs prod) — variable misconfiguration that resolves a stg deployment to prod secret paths has caused real outages

## OOB-then-Codify Reporting

When you apply a change out-of-band before the codifying PR merges (e.g., `aws iam attach-role-policy`, `kubectl patch`, `terraform apply` from a worktree), every status update MUST start with the live-state line:

```text
Live state: applied OOB at HH:MM via `<command>`. Repo state: PR #N codifies. Diff between them: none.
```

Burying the OOB-applied line forces the user to ask "did we apply?" / "changes applied?" — repeat that pattern and you waste 1–3 turns per cycle.

## General: When Something Goes Wrong

1. **STOP.** Do not rush to fix.
2. **Assess current state** — query the live system. What is the actual damage?
3. **Capture current (broken) state** — save it. You'll need it for post-mortem.
4. **Identify root cause** — why did the original action fail? What assumption was wrong?
5. **Plan the fix** — present to the user. Get explicit approval.
6. **Execute fix** — following the full protocol (pre-action, action, post-action).
7. **Verify fix** — both from admin view and consumer perspective.
8. **Report** — what happened, why, what was fixed, what was verified.
