# Scoped GHA OIDC role policies must copy a canonical action set per resource type, not enumerate by hand

## Symptom

A `workflow_dispatch` / `workflow_run` invocation that uses `aws-actions/configure-aws-credentials` with a scoped OIDC role succeeds at the AssumeRoleWithWebIdentity step, then dies mid-`terraform plan` or mid-`terraform apply` with `AccessDenied: User: arn:aws:sts::<acct>:assumed-role/<scoped-role>/<session> is not authorized to perform: <action> on resource: <arn>`.

Each fix unblocks the next step; the next step reveals the next missing single action. N reactive PRs across one incident, surfaced one workflow run at a time.

## Mechanism

The AWS Terraform provider issues **eager per-attribute reads** on every `plan` refresh. `aws_s3_bucket` alone causes ACL, CORS, logging, ownership, replication, request-payment, website and accelerate reads — listing only some causes single-action AccessDenied per refresh attempt. The same shape applies to RDS, ElastiCache, EKS and any other resource family with rich attribute surfaces.

A scoped GHA role's authorization spans three layers, each independently capable of producing this failure:

1. **Trust** — does its `assume_role_policy` allow the GitHub OIDC token *and* does any role it chains into (e.g. a shared `<state-role>`) trust *it* in turn?
2. **Policy attachment** — is the right *policy* in the role's `aws_iam_role_policy_attachment` set? A role can have correct trust and still fail mid-workflow because the policy that grants the relevant resource actions was never attached.
3. **Action coverage inside each policy** — does the policy enumerate every API the provider eagerly calls for the declared resources?

Audits that scope to one layer leave the other two as land mines. AWS doesn't surface "this policy is incomplete for the workload it'll run" — it surfaces "denied at runtime, action by action."

## Rule

**The end-to-end gate before declaring any scoped GHA role authoring/extension done is a `terraform plan` from a fresh-state target (e.g. a new tenant or new deployment) with the scoped role assumed — not the admin SSO.** That single command exercises trust, attachment, and action coverage in one shot for every resource type the workflow will refresh.

To converge that plan when it fails:

1. Identify the resource type from the failing AccessDenied log line.
2. Find the canonical block in your IAM data file that already manages the same resource type.
   - **Preferred**: a sibling policy in the same file. A canonical S3-bucket-level SID (e.g. `ManagedBucketsBucketLevel`) lists every Get/Describe/Put/Delete sibling action.
   - **Fallback**: HashiCorp's per-resource IAM permission docs (each `aws_<x>` page has a "Permissions" section).
   - **Never**: enumerate from memory.
3. Copy the **entire** canonical action list — both `Get*`/`Describe*` and `Put*`/`Delete*`/`Modify*` siblings. Adding only the denied action is the death-by-1000-cuts pattern.
4. Apply via `terraform apply` from your worktree (workspaces without auto-apply CI need manual apply), then re-run the plan-only gate.
5. Verify the trust chain explicitly: role's own `assume_role_policy` accepts the OIDC subject, and every chained role (a shared `<state-role>` is the common case) lists this role's ARN.

The plan-only gate from step 1 is the contract; everything else is bookkeeping that exists because that gate failed.

## Counter-indications

- Does **not** apply to non-TF roles (workflows that only call AWS APIs directly via the AWS CLI). Their action surface is bounded by the script, not by a TF provider's eager-read behavior. Direct enumeration from the script's API calls is sufficient.
- Does **not** apply to roles whose trust is via service principal or federated identity rather than role-to-role chaining (no shared state role involvement). Layer 1 collapses to "does the trust statement match the actual `Service`/OIDC subject."
- Trust-policy additions still follow the incremental rule in `iam-trust-policy-incremental.md` — that rule governs *how* to add a principal; this rule governs *what coverage to verify before declaring done*.
- **Does** apply to plan-only CI roles. The provider's refresh phase issues the same eager per-attribute reads during `terraform plan` as during `apply`; restricting the role to `Get*`/`List*`/`Describe*` is sufficient for actions but the action *set* must still be complete per resource type.

## Reference

Pin a canonical action-set SID (e.g. for S3 bucket-level actions) in your shared IAM data file and reference it from new scoped roles. Other resource families (IAM, RDS, EC2, EKS, etc.) have analogous canonical blocks in the AWS provider docs — check there first before authoring fresh.
