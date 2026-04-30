# Self-Hosted GitHub Actions Runners on EKS (ARC scale-set mode)

Reference for self-hosted runners deployed via [actions-runner-controller](https://github.com/actions/actions-runner-controller) (ARC) in scale-set mode on EKS.

> **What's universal vs example:** the **standard debug sequence** and **known failure modes** sections are universal-for-ARC — same `kubectl` commands and failure shapes regardless of how you organize your scale sets. The **topology**, **scale-set pattern**, **resource sizing**, and **image build/deploy flow** below are one team's specific layout — they illustrate decisions you'll need to make, not a recipe to copy. Adapt the scale-set decomposition to your actual workload mix.

## Topology

- **Cluster:** EKS cluster of your choice
- **Namespace:** typically `arc-runners`
- **ARC chart:** `gha-runner-scale-set-controller` + `gha-runner-scale-set` (matching version)
- **Auth:** GitHub App, credentials stored in your secrets manager and synced into the cluster via External Secrets

## Scale Set Pattern

Each scale set declares a `runs-on` label, an image, a container mode, max runners, and a node selector:

| `runs-on` label | Image kind | Container mode | Node selector |
|---|---|---|---|
| `<org>-gha-rs-set` | base ops image | kubernetes | `your-label/deployment=gha` |
| `<org>-gha-rs-set-dind` | docker image | dind (sidecar) | `your-label/deployment=gha-dind` |
| `<org>-gha-rs-set-storage` | lint image with EBS PVC | kubernetes + EBS | `your-label/deployment=gha` |
| `<org>-gha-rs-set-terraform` | terraform image | kubernetes | `your-label/deployment=gha` |

Controller pod runs on `karpenter.sh/capacity-type=on-demand` nodes. dind nodes have a `gha-dind:NoSchedule` taint; non-dind nodes have `gha:NoSchedule`. Pods tolerate the matching taint via the scale-set's `template.spec.tolerations`.

## Resource sizing (per runner pod)

Approximate sizes that have worked well in practice — adjust to your workload mix:

| Scale set | CPU req/limit | Memory req/limit | Storage |
|---|---|---|---|
| ops / terraform / data | 3 / 6 | 5 / 14 GiB | emptyDir |
| storage (EBS PVC) | 3 / 6 | 8 / 16 GiB | 50 GiB EBS |
| dind runner container | 4 / 8 | 8 / 32 GiB | 30 / 100 GiB |
| dind sidecar | 2 / 4 | 4 / 8 GiB | 20 / 50 GiB |

## Image build/deploy flow

A typical pipeline:

1. PR to the infra repo touching the runner Dockerfile / build context → build-only job (no push).
2. Merge to `main` → reusable workflow builds all runner image targets in parallel (matrix), pushes `latest` + `sha-<SHA>` tags to ECR.
3. Scale-sets pick up `:latest` on next pod restart. Module-level `recreate_pods = true` cycles them, but for ARC chart upgrades a follow-up `terraform apply` is usually required.

## Standard Debug Sequence

### 1. Is the job queued or running?

```bash
kubectl --context <cluster> -n arc-runners get pods -o wide
kubectl --context <cluster> -n arc-runners get autoscalingrunnerset
kubectl --context <cluster> -n arc-runners get ephemeralrunner
```

### 2. Controller health

```bash
kubectl --context <cluster> -n arc-runners get deployment
kubectl --context <cluster> -n arc-runners logs deployment/<controller-name> --tail=100
```

### 3. Listener health (one per scale-set)

```bash
kubectl --context <cluster> -n arc-runners get pods -l actions.github.com/scale-set-name=<scale-set-name>
kubectl --context <cluster> -n arc-runners logs <listener-pod> --tail=100
```

### 4. Runner pod status

```bash
kubectl --context <cluster> -n arc-runners get pods --field-selector=status.phase=Pending
kubectl --context <cluster> -n arc-runners describe pod <runner-pod>
kubectl --context <cluster> -n arc-runners logs <runner-pod> -c runner --tail=100
kubectl --context <cluster> -n arc-runners logs <runner-pod> -c dind --tail=100   # dind only
```

### 5. Node capacity (Karpenter)

```bash
kubectl --context <cluster> get nodes -l your-label/deployment=gha
kubectl --context <cluster> get nodes -l your-label/deployment=gha-dind
kubectl --context <cluster> get nodeclaim -l karpenter.sh/nodepool | grep gha
```

### 6. ECR image pull errors

```bash
kubectl --context <cluster> -n arc-runners get pods | grep -E "ImagePullBackOff|ErrImagePull"
kubectl --context <cluster> -n arc-runners describe pod <pod> | grep -A10 "Events:"
```

If ECR pull fails, verify the node IAM role has `ecr:GetAuthorizationToken` + `ecr:BatchGetImage` for the registry account.

## Known Failure Modes

- **ECR pull errors on dind nodes** — dind pulls upstream `docker:dind` typically via an ECR pull-through cache. If the cache is stale or the node IAM role lacks ECR perms, the dind init container fails. Check node IAM role + the cache-warmup workflow.
- **Runners stuck in Pending — no node scale-up** — Karpenter NodePools for `gha` and `gha-dind` have separate `NoSchedule` taints. A runner pod with a mismatched taint or wrong `nodeSelector` will never schedule. Verify the `deployment-id` label on the NodePool matches the scale-set's selector.
- **Storage set slow to start** — EBS PVC provisioning adds 30–60s. If it hangs >5 min, `kubectl describe pvc` for provisioner errors.
- **`apt-get` HTTP blocked** — If you patch all apt sources to HTTPS on startup (e.g., HTTP/80 blocked by SG / NACL egress), a new apt source added with HTTP will fail the image build at `apt-get update`. Rebuild path: catch new HTTP sources at lint time, or add an early `sed` step that rewrites them.
- **Runner group missing** — Runner groups must exist in the GitHub org BEFORE the first `terraform apply`. ARC registration fails silently if the group is missing.
- **`ACTIONS_RUNNER_REQUIRE_JOB_CONTAINER=false`** — All non-dind runners typically set this. Jobs run directly in the runner container, NOT in any `container:` block specified in the workflow. Intentional, but surprising — workflows that assume isolation via `container:` don't get it.
- **Terraform provider mirror stale** — Bake a mirror at runner image build time from existing `.terraform.lock.hcl` files. New TF module with a new provider → `terraform init` falls back to direct download. If direct download is blocked, init fails. Fix: add the new lock file, rebuild the `terraform` runner image.

## Observability

- **Whisker + Goldmane** for in-cluster network-policy flow visibility (see `network-policies-audit.md`).
- **Datadog / pup CLI** for runner pod metrics — alert thresholds on pending runner count should be set well above the natural workload spike (e.g. warning=25, critical=40), not at low single-digits, or you'll alert on every legitimate burst.
