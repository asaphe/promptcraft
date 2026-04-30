# Terraform Discipline (root configs)

Authoring and safety rules for root Terraform configurations — the configs that consume reusable modules and hold state.

> A subset of these rules assume a **config-driven module pattern** (`terraform.workspace` + `vars/*.json` or `vars/*.tfvars` selecting per-workspace config). Rules that depend on that pattern are flagged below. The provider-mechanics rules (lockfile, fmt, module pinning, data-source placement, S3 backend hygiene, mode-encoding via `count`/`for_each`) apply regardless of how you structure inputs.

## Authoring (assumes config-driven pattern)

- **Config files drive everything** — Routine changes are `vars/*.json` or `vars/*.tfvars` edits, not `.tf` changes. Only modify `.tf` files for new resource types or structural changes.

- **Workspace = team / tenant / env name** — Every module uses `terraform.workspace` to select config from `vars/`. Never hardcode workspace-derived values in `.tf` files. Adapt to your own workspace naming if you don't use this scheme.

- **Pin Terraform version via `.terraform-version`** — Single source of truth for the version. Never use `required_version` in `versions.tf` — version pinning is handled by `.terraform-version` and your TF wrapper (tfenv, asdf, mise).

- **Pin module sources by SHA or version, never branch** — git source: pinned commit SHA. Registry source: pinned version. Branch references silently shift across applies.

- **Run `terraform fmt`** on all `.tf` and `.tfvars` files before committing.

- **Validate JSON config** — Run `jq .` on modified `vars/*.json` files to catch syntax errors before plan.

- **General-purpose data sources in `data.tf`; domain-specific ones may be co-located** — `data "aws_caller_identity"`, `data "aws_eks_cluster"`, and similar general references belong in `data.tf` so cross-file dependencies are traceable. Domain-scoped blocks (`data "aws_iam_policy_document"`, `data "aws_secretsmanager_secret_version"` tied to a single resource) may live in a descriptively named file (e.g. `iam_data.tf`, `secretsmanager.tf`) alongside the resources that consume them. Placing general data sources in `main.tf` or `variables.tf` is the pattern to avoid.

## Safety

- **S3 backend with `use_lockfile = true`** — All state in a single dedicated bucket. Never change backend config without team coordination — a backend change orphans state.

- **`workspace_key_prefix` must match the module path** — Format: `<domain>/<resource_type>` or similar predictable structure.

- **CI auto-applies on merge** — Changes to `vars/*.json` typically trigger automatic `terraform apply` when merged to main. Review carefully — there's no staging step.

- **Files that enumerate resources to import (`imports.tf`, recovery / panic-button manifests) describe post-apply state, not initial-plan state** — Applies if your repo maintains such files. Every resource that exists POST-APPLY must be in such a file. If a resource transitions "doesn't exist → exists" mid-PR (because the PR creates it), re-evaluate every such artifact and add the missing entry before merge.

## Patterns

- **Use `try(..., [])` for resilience** — Wrap `fileset()` and `jsondecode()` in `try()` in `locals.tf` so missing files don't crash plan.

- **New resource types need CI workflow matrix entries** — Add the type to `resource_type` dispatch choices and path filters.

- **Encode mode-dependent correctness with `count` / `for_each`, not external registry conventions** — When the correctness of a resource or grant depends on a runtime mode (single-tenant vs multi-tenant, env, deployment type, tenant scope) that isn't itself a TF input being consumed by the resource, encode the gate structurally — `count = local.<mode> ? 1 : 0`, `for_each = { for k,v in <map> : k => v if <mode-predicate> }`, conditional `dynamic` blocks, or keying maps by `(application, mode)`. Do **not** rely on external config (registry JSON, naming conventions, allowlists in another module) to keep things consistent. External-config-as-enforcement fails silently when someone adds a new entry that doesn't match the convention. The TF graph itself must reject the wrong shape; the registry alone won't.
