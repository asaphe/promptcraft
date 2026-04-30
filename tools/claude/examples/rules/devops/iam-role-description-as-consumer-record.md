# IAM role descriptions as a queryable consumer record — keep them in sync with assuming workflows

> **When this rule applies:** if your team uses the IAM role's `description` field as the canonical record of "what assumes this role" (a common workaround given that IAM doesn't surface consumer relationships natively). If you maintain the same record elsewhere — tags, a wiki, a service catalog, a Lucidchart — apply the equivalent atomicity rule to that record. The principle is universal; the specific record location is your team's choice.

## Symptom

A scoped IAM role's `aws_iam_role.description` field claims a fixed set of consuming workflows, but the actual set has drifted — workflows added without updating the description, or removed/renamed without cleanup. An audit reads the description, takes it as truth, and reaches a wrong conclusion about which CI surfaces would break if the role is changed.

## Mechanism

IAM does not surface the consumer relationship anywhere queryable: `aws iam get-role` returns trust policy, attached policies, and description — not "which workflows actually assume me." The trust policy can constrain which OIDC subjects are allowed (`token.actions.githubusercontent.com:sub` matchers, `job_workflow_ref` conditions), but reading those constraints back into a workflow list is error-prone and frequently outdated as repo/branch refs evolve.

The `description` field is the only human-readable, queryable record that names which workflows assume the role. When it drifts, PR-time confusion ("which workflows would this trust-policy change break?") compounds into audit-time wrong conclusions ("the description says only X assumes this role, so we can deprecate Y safely") — both errors made silently because nothing in IAM forces the description to stay accurate.

## Rule

**Any change that adds, removes, or renames a consumer of a scoped IAM role must update the role's `description` field in the same change.** A consumer is whatever entity actually assumes the role — a workflow file, a Kubernetes ServiceAccount + namespace (for IRSA), a Lambda function, etc. The description must name them.

This applies symmetrically:

- **Adding a new role**: write the description with the full enumerated consumer list at creation time. If you don't know all consumers yet, the role isn't ready to merge.
- **Adding a new consumer of an existing role**: append the consumer (workflow filename, SA+namespace, Lambda name) to the role's description in the same PR. The PR that wires up the trust must also update the human-readable record.
- **Removing or renaming a consumer**: delete or rename the entry in the role's description. Stale entries are worse than missing ones — they assert false coverage.
- **Splitting / merging roles**: descriptions on both sides reflect the post-change consumer set, not the pre-change set.

The discriminator: someone reading only the role's description (no access to git log or repo files) should be able to answer "what assumes this role?" correctly. If they can't, the description is stale.

## Counter-indications

- Does not apply to roles whose consumers are AWS service principals (`Service: lambda.amazonaws.com`, `Service: ec2.amazonaws.com`) — those are static and named in the trust policy itself; the description can be brief.
- Does not apply to roles with **wildcard trust** (e.g., a `repo:org/*` OIDC subject pattern that intentionally accepts any repo or any workflow) — enumerating consumers there doesn't scale and isn't the point of the role. The description should state the wildcard intent and the constraint that bounds it.
- Does not apply to **third-party SaaS / external system roles** assumed via cross-account trust (e.g., observability vendors, security scanners) where the consumer is the external account itself and the workflow surface is opaque. Description should name the integration and the external account/role on the other side.
- Does not apply to break-glass / console-managed roles deliberately excluded from automation — their description should explicitly state the break-glass intent so a future reader doesn't try to wire them into a workflow.

## Related

Trust-policy mechanics for adding/removing scoped roles are covered in `iam-trust-policy-incremental.md`. That rule governs *how* to mutate a trust policy safely; this rule governs *what record of consumers must move with it*.
