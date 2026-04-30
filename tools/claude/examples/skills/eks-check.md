---
name: eks-check
description: Run the standard EKS diagnostic sequence for a failing/pending/crashlooping pod or syncing issue. Usage - /eks-check [namespace] [pod-name-or-label] [optional context]
user-invocable: true
allowed-tools: Bash(kubectl *), Bash(helm *), Bash(aws *), Bash(ls *), Bash(cd *), Bash(cat *), Read, AskUserQuestion
argument-hint: "[namespace] [pod-name|-l label-selector] [--context <ctx>]"
---

# EKS Quick Check

Standard diagnostic sequence — use when the user says: `check EKS`, `pod is failing`, `ESO not syncing`, `pending pods`, `check the cluster`.

> **Stack assumptions:** this skill assumes EKS + ExternalSecrets Operator + Karpenter. The branch table at step 5 jumps to ExternalSecret CRD on mount errors and step 7 references Karpenter `nodepool` and `karpenter` namespace logs. Adapt or remove those branches if your stack uses a different secrets operator or autoscaler.

This skill executes the most-common subset of an EKS diagnostic runbook and reports a structured summary so the user doesn't have to re-derive the steps each time. Pair with a fuller runbook of your own for less common failure modes.

## Inputs

`$ARGUMENTS` may be:

- empty → ask for namespace
- `<namespace>` → list pods in that namespace
- `<namespace> <pod-name>` → diagnose that specific pod
- `<namespace> -l <label-selector>` → diagnose pods matching label
- `--context <ctx> ...` → use a specific cluster context (default: your primary cluster)

## Steps

### 1. Resolve target

Parse `$ARGUMENTS`. If no namespace supplied, ask the user.

### 2. Private-endpoint preflight

If the target cluster has a private API endpoint (no internet-routable kube-apiserver), confirm the appropriate VPN is connected before issuing kubectl commands. A private-endpoint cluster from a disconnected client times out with `dial tcp 10.x.x.x:443` after ~30s — a generic "API timeout" without VPN context will lead to dead-end debugging. Surface this preflight before any kubectl call.

### 3. Pod state

```bash
kubectl --context <ctx> -n <namespace> get pods <target> -o wide
```

If `<target>` is empty, list all pods in namespace. Note any non-Running phases: `Pending`, `CrashLoopBackOff`, `ImagePullBackOff`, `Init:Error`, `RunContainerError`, `Terminating`.

### 4. Pod events (the most informative single command)

```bash
kubectl --context <ctx> -n <namespace> describe pod <pod> | tail -50
```

Extract the `Events:` section. Surface the most recent failure reason verbatim.

### 5. Branch by event reason

Match the failure to the appropriate next step:

| Event reason | Next step |
|---|---|
| `FailedScheduling` | Step 7 — Karpenter / NodePool / taints |
| `Failed to pull image` / `ErrImagePull` | Step 7b — image registry auth, image tag, IRSA |
| `MountVolume.SetUp failed` (secret/configmap) | Step 5b — ExternalSecret status |
| `Liveness/Readiness probe failed` | Step 6 — pod logs |
| `OOMKilled` | Resource limits + observability memory graph |
| Container `Error` / `CrashLoopBackOff` (no specific event) | Step 6 — pod logs |

### 5b. ExternalSecret status (if mount/secret event)

```bash
kubectl --context <ctx> -n <namespace> get externalsecret
kubectl --context <ctx> -n <namespace> describe externalsecret <name>
```

If `STATUS=SecretSyncedError`, run ESO controller logs filtered for the secret name:

```bash
kubectl --context <ctx> -n external-secrets logs -l app.kubernetes.io/name=external-secrets --tail=200 | grep -i <secret>
```

Verify the SM path exists: `aws secretsmanager describe-secret --secret-id <path>`.

### 6. Pod logs

```bash
kubectl --context <ctx> -n <namespace> logs <pod> --tail=200
kubectl --context <ctx> -n <namespace> logs <pod> --previous --tail=200   # if CrashLoopBackOff
```

For multi-container pods, add `-c <container>`. For init container failures: `-c <init-container>`.

### 7. Capacity (FailedScheduling)

```bash
kubectl --context <ctx> get nodes
kubectl --context <ctx> get nodepool   # Karpenter clusters
kubectl --context <ctx> -n karpenter logs -l app.kubernetes.io/name=karpenter --tail=200 | grep -i <pod>
```

### 7b. Image registry / pull issues

Verify the image tag exists in your registry:

```bash
aws ecr describe-images --repository-name <repo> --image-ids imageTag=<tag>
```

If pull failure on a self-hosted runner pod, check runner-specific image-pull failure modes (cached image expiry, registry auth refresh).

### 8. Helm release state (only if deploy itself looks broken)

```bash
helm --kube-context <ctx> -n <namespace> list -a
helm --kube-context <ctx> -n <namespace> status <release> --show-resources
```

If `pending-rollback` / `pending-upgrade`, see the `helm rollback after uninstall --keep-history is broken` rule — this is a known Helm bug; the release is stuck and needs manual recovery (delete and redeploy), not another rollback attempt.

## Output

Report structure (don't pad — keep it scannable):

```text
## EKS check: <namespace>/<target> (context: <ctx>)

State: <phase> <reason>
Latest event: <verbatim event line>
Hypothesis: <one-line root cause>

Evidence:
- <key kubectl output line>
- <key kubectl output line>

Next action: <one-line — fix code | apply terraform | escalate | wait>
```

If diagnosis is incomplete (e.g., need to wait for next event, or VPN required), say so explicitly. Don't fabricate a hypothesis without evidence.

## Safety

- Read-only diagnostics. This skill does NOT mutate cluster state — never run `kubectl delete`, `kubectl apply`, `helm upgrade`, etc. from within this skill.
- If the user's intended action is a fix, surface the proposed fix and ask before applying.
