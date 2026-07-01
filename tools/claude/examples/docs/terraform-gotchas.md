# Terraform Gotchas

Non-obvious Terraform patterns that have caused failures.

---

## Conditional return types must match exactly

```hcl
# BROKEN — fails at plan time:
# "Inconsistent conditional result types — attribute types must all match for conversion to map."
local.x = var.flag ? var.databases : {
  for k, v in var.databases : k => merge(v, {users = ...})
}
```

`merge(typed_object, {...})` returns a synthesized object whose inferred type can differ from `var.databases`'s `map(object({...}))` schema (after `optional()` materialization). The conditional rejects the mismatch.

Fixes:

- Construct both branches explicitly with all attributes (typed match guaranteed), OR
- Drop the conditional and use a single comprehension with conditional logic on individual fields/filter predicates.

`terraform fmt` and `terraform validate` (against an empty workspace) miss this. Only `terraform plan` against a real workspace catches it. **Pre-merge plan for non-trivial conditional locals is required.**

---

## Cluster-scoped k8s resources belong in cluster-keyed TF workspaces

`PriorityClass`, `ClusterRole`, `ClusterRoleBinding`, `StorageClass`, `Namespace`, `CustomResourceDefinition` etc. are cluster-scoped — one object per cluster, not per namespace. Defining them inside a per-deployment workspace makes the first deployment's apply win and every subsequent deployment's apply fail with `<resource> "<name>" already exists`.

Place them under a cluster-keyed path (e.g. `terraform/eks/<purpose>/`) with workspace key `{env}_{cluster}`. If a per-deployment path IS keyed per-cluster (workspace pattern `{env}_{cluster}_<region>`), the placement is functional but the path naming is misleading and worth fixing. Per-deployment placement of a cluster-scoped resource is the actual bug.

---

## `removed { lifecycle.destroy = false }` for cross-workspace ownership migration

When migrating ownership of a cluster-scoped object from N existing TF workspaces to a single new workspace:

1. Define the resource in the new workspace.
2. `terraform import` it into the new workspace's state (object already exists, no actual change).
3. Add `removed { from = <old_address>; lifecycle { destroy = false } }` to the existing module's HCL.
4. Each existing workspace's next apply self-cleans state via the `removed` block — no destroy.

```hcl
removed {
  from = kubernetes_priority_class_v1.batch_workload

  lifecycle {
    destroy = false
  }
}
```

Scales to any number of existing workspaces without manual `terraform state rm` per workspace. No-op for workspaces that never had the resource in state.

Related: see `terraform-state-moves.md` for moving a resource between modules within the same workspace's state.

---

## Filter ALL related dimensions when removing a resource bundle

If a TF feature flag filters resources via `local.X = var.flag ? var.X : { filtered }`, ensure the filter covers EVERY dimension where the bundle's identity appears.

Concrete failure mode: PostgreSQL roles are cluster-scoped. If the same role name appears in multiple databases AND your TF derives a "canonical" entry per role-name (e.g., first alphabetically) before creating the role + secret, then filtering only top-level keys can shift the canonical to a different database. TF plans DESTROY of the old canonical address + CREATE of the new one — the cluster-scoped role can't exist twice, the create races the destroy, apply fails with "role X already exists".

When a `<prefix>*` filter is meant to remove "everything <prefix>", filter:

- Top-level keys (databases, modules)
- User maps inside each remaining item
- `default_privilege_owners` and similar role-name lists
- Any other place the filter target's identity appears

The pre-merge plan is the verification that catches missed dimensions — every resource address in the destroy plan should be expected, every CREATE should be expected.

---

## `terraform destroy` over `terraform state rm` for orphan cleanup

When a partial apply leaves real AWS/K8s objects in a TF workspace that's being abandoned, `terraform state rm` only removes the state entry — the underlying objects remain as orphans. Use `terraform destroy` instead so TF actually deletes the objects, then `terraform workspace delete` to remove the now-empty workspace from the backend.

Always:

```bash
terraform state pull > /tmp/<workspace>-backup-<date>.json   # rollback payload
terraform plan -destroy -var-file=...                        # verify destroy list
terraform destroy -auto-approve -var-file=...                # apply
terraform workspace select default && terraform workspace delete <ws>
```

---

## EKS pod IAM auth: Pod Identity vs IRSA

The two mechanisms are not interchangeable, and mixing them silently fails. **EKS Pod Identity** uses `aws_eks_pod_identity_association` + service principal `pods.eks.amazonaws.com` with `Action: sts:AssumeRole`. **IRSA** uses an OIDC trust policy with `sts:AssumeRoleWithWebIdentity`. Decide which the cluster uses and be consistent — do not write an IRSA trust policy for a Pod Identity cluster (or vice versa). The wrong trust principal/action produces auth failures that don't surface until the pod tries to call AWS.

---

## Pre-merge plan: only `terraform plan` against a real workspace catches type-sensitive bugs

Mandate an apply plan for any PR with `.tf` changes. The TF-specific reason: `terraform fmt` validates syntax only, and `terraform validate` runs against the `default` workspace (which often doesn't satisfy workspace-name parsing in workspace-keyed locals). Only `plan` against a real workspace exercises the full type system + state diff under realistic inputs.

Specifically, conditional return-type mismatches (`merge()` producing a synthesized type that doesn't match the typed branch) surface ONLY at plan time. For non-trivial conditional locals, `for` expressions, or filter logic on shared resources, plan against an affected workspace is the only adequate verification.

---

## Prefer direct state fixes over leftover `removed`/`moved` scaffolding

For drift, mis-addressed resources, or moves **within a single workspace's state**, fix the state directly (`terraform state mv`, `terraform import`, `terraform state rm`) rather than leaving `removed`/`moved` blocks in the HCL as permanent scaffolding. Temporary scaffolding code outlives its purpose and confuses the next reader.

The exception is **cross-workspace ownership migration** (the `removed { lifecycle.destroy = false }` recipe above): there the `removed` block is the scaling tool because it self-cleans N existing workspaces without a manual `state rm` per workspace. Reserve `removed`/`moved` for that case; for same-workspace fixes, edit state directly.

---

## Import manual resources, don't build workarounds

When you discover an AWS/K8s resource created outside Terraform, `terraform import` it into the managing workspace and codify it in HCL — do not write conditional logic, data sources, or `ignore_changes` blocks to route around the un-managed object. Importing brings it under the same plan/apply discipline as everything else; workarounds accumulate as drift the next operator can't reason about.

---

## Parallel TF workspace copies need `.terraform/`

To run a second workspace copy in parallel (e.g. a scratch plan while another applies), copy the directory **with** its `.terraform/` and then `terraform init -reconfigure`. The go-getter SDK path cannot bootstrap SSO / `credential_process` from a bare directory — without the pre-existing `.terraform/` the init fails to resolve credentials.

---

## zsh GLOB_DOTS makes `*` match hidden files

Under zsh with `GLOB_DOTS`, `cp -r dir/* dest/` also copies `.terraform/`, `.gitignore`, and other dotfiles — silently dragging stale provider state into the copy. When you need to exclude hidden files, pass an explicit file list instead of relying on `*`.

---

## Branch-deadness / flatten verification needs the full file, not excerpts

Determining which side of a conditional is dead (before flattening a ternary, removing a branch, collapsing a `count`/`for_each` gate) requires the *full* file plus a `terraform plan` byte-compare across affected workspaces. Delegating this to a subagent reading excerpts fails repeatedly — excerpts hide the cross-file references (data sources, IAM tags, fallback locals) that decide which branch is live.

The verification of record is full-file read + a byte-compare of the affected expressions across every distinct **workspace-string shape** — one representative per shape (env-prefix, part-count, region variant), since workspace-derived locals are pure functions of the workspace string, so per-shape coverage is exhaustive and sweeping all N workspaces is wasted work. When the change is pure-structure (locals computed only from `terraform.workspace` + vars, no data-source/state reads), `terraform console` on the changed locals per representative shape suffices; reserve a full `terraform plan` byte-compare across **every** live workspace for changes whose output depends on live state/data sources (where per-workspace drift can differ).
