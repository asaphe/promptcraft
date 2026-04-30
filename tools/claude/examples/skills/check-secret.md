---
name: check-secret
description: Inspect and compare secrets across AWS Secrets Manager, ExternalSecret CRDs, Kubernetes secrets, and pod environment. Detects drift and mismatches. Usage - /check-secret [application] [deployment]
user-invocable: true
allowed-tools: Bash(kubectl *), Bash(aws *), AskUserQuestion, Read, Grep, Glob
argument-hint: "[application] [deployment-name]"
---

# Check Secret

Secret inspection and drift detection across the full secret chain — AWS Secrets Manager → External Secrets Operator → Kubernetes Secret → pod environment.

## Steps

### 1. Determine parameters

If `$ARGUMENTS` is provided, parse application and deployment / namespace from it. Otherwise, ask:

1. **Application**: Which service to check
2. **Deployment / namespace**: Where the workload runs

### 2. Find ExternalSecret CRDs

```bash
kubectl get externalsecret -n {namespace} -o json | jq '[.items[] | select(.metadata.name | test("{application}"))] | .[].metadata.name'
```

If no exact match, list all ExternalSecrets in the namespace:

```bash
kubectl get externalsecret -n {namespace} -o wide
```

Ask the user which one to inspect.

### 3. Get ExternalSecret details

```bash
kubectl get externalsecret {name} -n {namespace} -o json | jq '{
  status: .status.conditions[-1].type,
  message: .status.conditions[-1].message,
  refreshInterval: .spec.refreshInterval,
  secretStore: .spec.secretStoreRef.name,
  targetSecret: .spec.target.name,
  remoteRefs: [.spec.data[] | {key: .secretKey, remoteKey: .remoteRef.key}]
}'
```

### 4. Fetch AWS Secrets Manager value

For each remote ref found:

```bash
aws secretsmanager get-secret-value \
  --secret-id {remoteRef.key} \
  --query 'SecretString' \
  --output text | jq 'keys' 2>/dev/null || echo "Not JSON or not found"
```

Record the keys present in the AWS secret. **Never print secret values — only keys and presence.**

### 5. Fetch Kubernetes secret

```bash
kubectl get secret {targetSecret} -n {namespace} -o json | jq '{
  keys: (.data | keys),
  age: .metadata.creationTimestamp
}'
```

### 6. Check pod environment

```bash
kubectl exec -n {namespace} deploy/{application} -- env 2>/dev/null | sort
```

If exec fails (no running pod, RBAC denial), note this and skip.

### 7. Compare and report

Present a comparison table:

```text
Secret Chain: {application} in {namespace}
═══════════════════════════════════════════

ExternalSecret: {name}
  Status: SecretSynced
  Store:  aws-secrets-manager
  Refresh: 1h

Key Comparison:
┌─────────────────────────┬───────┬──────┬──────┐
│ Key                     │ AWS   │ K8s  │ Pod  │
├─────────────────────────┼───────┼──────┼──────┤
│ DATABASE_URL            │  ✓    │  ✓   │  ✓   │
│ REDIS_URL               │  ✓    │  ✓   │  ✗   │  ← DRIFT
│ OLD_UNUSED_KEY          │  ✗    │  ✓   │  ✗   │  ← STALE
└─────────────────────────┴───────┴──────┴──────┘

Findings:
  - DRIFT: REDIS_URL present in AWS SM and K8s secret but not in pod env
  - STALE: OLD_UNUSED_KEY in K8s secret but not in AWS SM (stale from previous sync?)
```

### 8. Suggest remediation

Based on findings:

- **DRIFT (AWS → K8s mismatch)**: Force ESO re-sync via annotation refresh:
  `kubectl annotate externalsecret {name} -n {namespace} force-sync=$(date +%s) --overwrite`
- **STALE (K8s has keys not in AWS)**: May need to delete and recreate the K8s secret. ESO doesn't remove keys when AWS removes them — only adds and updates. Stale entries persist forever.
- **Pod missing key**: Check the deployment spec — is the secret mounted correctly? Is the env var declared via `valueFrom.secretKeyRef`?
- **All match**: Confirm the chain is healthy.

## Safety

- Read-only for AWS Secrets Manager and Kubernetes secrets — no modifications without explicit approval
- `kubectl exec ... -- env` only reads env vars, does not modify the pod
- If exec is denied by RBAC, note it and present partial results
- **Never print secret values** — only compare keys and presence
