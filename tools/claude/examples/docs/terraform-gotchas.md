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

## A `check` block over a for-expression is vacuously true when the collection is empty

`alltrue([])` is `true`. So a guard like `alltrue([for x in local.allowlist : startswith(x, "prod-")])` passes trivially the moment `local.allowlist` becomes empty — emptying the collection silently *disarms* the assertion instead of failing it. The same applies to `anytrue` / `alltrue` over any config-authored list, and to `for` comprehensions feeding `precondition` / `postcondition`.

Two fixes, both needed:

- **Assert over the rendered artifact, not the source collection** — `jsondecode()` the produced policy document (or the plan output) and assert on that, so the check is anchored to what actually ships.
- **Add a non-empty floor** — `length(local.allowlist) > 0` as its own assertion, so emptying the list fails loudly rather than passing quietly.

Generalizes past Terraform: **an assertion over a collection is only as strong as the collection is non-empty.** Any guard built from a comprehension can be neutered by emptying its input, so a size or shape floor belongs alongside every content assertion.

**Removing or inverting an existing assert needs a blast-radius pass**, because a guard frequently enforces a second invariant incidentally. Observed: flipping one positive pin (`x == "prod-foo"`) to a negative guard (`!startswith(x, "dev-")`) removed the only thing constraining the *shape* of every other entry, and a widened glob then passed every remaining assert. Before changing a guard, enumerate what else it was holding — not just the condition it names.

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

## A ForceNew replace whose dependent is keyed on an *unchanged* value never plans a detach

`aws_iam_policy.description` is ForceNew, so editing a policy's description replaces the policy. Whether that apply succeeds depends on how the attachment references it. Where the attachment's ARN is *constructed from the policy name* — `arn:aws:iam::${account}:policy/${name}` — rather than read from the policy's own `arn` output, the ARN string is byte-identical before and after, so Terraform plans the attachment as `no-op` and never detaches it. It then issues `DeletePolicy` against a policy with `AttachmentCount = 1`, and AWS returns `DeleteConflict` mid-apply.

Force the dependent to replace, which restores detach-before-delete ordering with no policy-name churn:

```bash
terraform plan -target=module.<role> \
  -replace='module.<role>.module.role.aws_iam_role_policy_attachment.this["0"]'
```

The plan should read `2 to add, 0 to change, 2 to destroy` — policy and attachment each delete-and-create, role `no-op` — and apply in the order attachment destroy → policy destroy → policy create → attachment create. The policy name, document and ARN are unchanged, so nothing referencing the ARN is affected.

The general shape, well beyond IAM: **when a replacement's dependent is keyed on a value the replacement does not change, Terraform sees no reason to touch the dependent, and the destroy fails on a constraint the plan never showed you.** Read the planned action for the *dependent*, not just for the resource you edited — a `no-op` there sitting alongside a `delete` is the warning sign.

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

---

## Provider-level `validate` / `-refresh=false` do not suppress a resource's own live API calls during plan

A "credential-less" or refresh-disabled PR-plan design assumes that a provider block's `validate = false`, and/or `terraform plan -refresh=false`, fully stop live authenticated calls to the upstream API during `plan`. That is not guaranteed — individual **resource types** can make their own live calls independent of both flags. Confirmed example: the Datadog provider's `datadog_monitor` resource calls `POST /api/v1/monitor/{id}/validate` and `datadog_role` calls `GET /api/v2/permissions` on every plan, regardless of either setting. A dummy or invalid credential then 401s on any workspace holding real resources of that type.

Before committing to a credential-less or refresh-disabled PR-plan design for any API-backed provider, run a real `terraform plan` with a throwaway *scoped* credential (not a dummy one) against a workspace with real resources, and confirm it succeeds. Do not infer suppression from a provider's documented flags — different resource types inside the same provider behave differently, and the only reliable check is empirical.

---

## `plan` and `console` disagreeing on the same expression means a concurrent writer, not nondeterminism

Symptom: a `check` block fails during `terraform plan` reporting a local as an empty tuple, while `terraform console` evaluates the identical expression to a full value seconds later. Re-running `plan` then succeeds, so it reads as provider flakiness or a graph-ordering race.

Cause, in the observed case: the `.tf` file was being edited — by a person or a parallel session — in the same worktree while `plan` was running. Terraform read a transient intermediate state. Nothing about the provider or the config was nondeterministic.

**Check for a concurrent writer before building a determinism harness.** `git status` and file mtimes cost seconds; a cold-`init` reproduction in a throwaway copy costs minutes and proves nothing if the file keeps moving. Generalizes past Terraform: when two evaluation paths disagree on one expression, suspect a writer between them before suspecting the evaluator.

Corollary — a *genuinely* flaky check block is worse than the bug it guards, so the two are worth distinguishing. Confirm determinism with repeated runs both warm and after a cold `terraform init`, and confirm the assert actually fires by injecting the case it targets.

---

## `terraform import` evaluates outputs against PRIOR state, so a faulting output breaks every import while `plan` stays green

`terraform plan` evaluates outputs against *planned* state; `terraform import` evaluates them against the state as it exists **before** the import. So an output expression that faults on an un-migrated or partially-migrated state shape aborts every import in that workspace, while plan and apply on the same config keep passing. Confirmed empirically on Terraform 1.15.8.

The failure surfaces as an error inside an `output` block during an operation that has nothing to do with outputs — for example `Attempt to get attribute from null value … user.auth is null`, emitted by `terraform import`. Nothing in the message points at the state shape, and the workspaces still carrying the old shape are usually a subset, so it reads as an import bug rather than a state-migration gap.

Two consequences worth acting on. An output that reads a *field the config no longer sets* is a latent import breaker — drop the coupling rather than defending it, since an unconsumed field in an output buys nothing. And when a schema migration lands, the workspaces to check are the ones that have not re-applied since, not the ones the change touched.

---

## A `state rm` + `import` recovery loop must snapshot and roll back, or a failed import orphans the resource

The `state rm` → `import` pair is the standard recovery when a provider's `Read` evicts a resource (a UUID lookup misses and there is no name-based fallback). `import` refuses to overwrite an existing entry, so the `rm` genuinely is required — which means there is a window where the resource is in **neither** state nor the plan graph. If the import then fails, the resource is silently orphaned, and the next apply tries to CREATE something that already exists, which fails on the name and keeps failing.

**Snapshot before the `rm`, fail closed if the snapshot cannot be taken, and push the snapshot back when the import fails.** The push needs a serial bump — the `rm` already advanced the live serial past the snapshot, so an unbumped push is rejected.

Test both branches before shipping such a loop: the happy path leaves the corrected id in state, and the failure path must leave the resource *still managed*. A local-backend copy of the real state, seeded with a deliberately wrong id, exercises both without touching remote state — but give the scratch workspace a **realistic name**, since modules routinely derive values from `split("_", terraform.workspace)` and a `default` workspace fails on an index that the real name satisfies.

The verification of record is full-file read + a byte-compare of the affected expressions across every distinct **workspace-string shape** — one representative per shape (env-prefix, part-count, region variant), since workspace-derived locals are pure functions of the workspace string, so per-shape coverage is exhaustive and sweeping all N workspaces is wasted work. When the change is pure-structure (locals computed only from `terraform.workspace` + vars, no data-source/state reads), `terraform console` on the changed locals per representative shape suffices; reserve a full `terraform plan` byte-compare across **every** live workspace for changes whose output depends on live state/data sources (where per-workspace drift can differ).
