---
paths:
  - "devops/terraform/**"
  - "devops/helm-reusable-chart/**"
---
# Terraform Apply & Variable Safety Rules

- **Manual apply picks up ALL code changes** — A terraform apply runs the current module code, not just your intended change. Before any manual apply, compare the current helm values (`helm get values --revision <last>`) against what terraform will generate. If there are unrelated changes beyond your intended diff, stop and flag them. The helm provider shows many values as `(known after apply)` which hides the actual diff.

- **Always resolve the running image tag before apply** — Modules default `image_tag` to `main` via `coalesce(var.image_tag, "main")`. Before any manual apply for helm-values or dagster modules: (1) check the running image: `kubectl get pods -o jsonpath='{.spec.containers[*].image}'`, (2) pass it explicitly: `-var='image_tag=<actual-tag>'`. Never rely on the module default.

- **`-target` is a last resort, not a workflow tool** — Use `-target` only in specific circumstances: recovering from errors Terraform explicitly flags, bootstrapping circular dependencies, or isolated emergency fixes. Never use it as a substitute for fixing state drift. The correct approach for state problems is: `terraform state mv` (resource address changed), `terraform import` (resource exists but isn't in state), or `terraform state rm` (orphaned/phantom entry), followed by a full plan/apply without targets.

- **state rm vs destroy — know the intent** — If the goal is to delete a cloud resource, use `terraform destroy -target`. If the goal is to remove tracking of a resource that should continue to exist (moved, imported elsewhere, managed by another module), use `terraform state rm`. Always state which you're using and why, and confirm with the user.

- **Workspaces — always list before creating** — Run `terraform workspace list` AND `aws s3 ls` against the state bucket before any workspace operation. Never create without presenting the proposed name and getting approval.

- **Verify `pwd` matches the intended Terraform module before every apply** — Before running `terraform apply` or `terraform plan`, run `pwd` and confirm it matches the module you intend to change. A wrong-directory apply silently modifies the wrong module's resources. After any `cd`, subshell, or tool that changes directory, re-verify before running Terraform commands.

- **Variable defaults must express the contract, not configuration** — Defaults should be type-shape values, not environment-specific config (account IDs, ARNs, hostnames, secret paths). Configuration belongs in one of three places:
  - `config.auto.tfvars` — auto-loaded by Terraform; use for singleton modules
  - `vars/*.tfvars` — passed via `-var-file`; use for multi-workspace modules
  - `TF_VAR_*` — injected by CI; use for deployment modules

  Acceptable defaults: `null` (required strings/objects), `false` (opt-in bools), `[]` (optional lists), `{}` (optional maps), `aws_region = "us-east-1"` (single-region, CI doesn't pass it), `owner = "devops"` (tag default). When fixing an existing module: move current default values to the appropriate config source before changing the default.

- **TF_VAR_owner must be the user, never "claude"** — For `TF_VAR_owner` or any ownership tag, use `$(whoami)` or ask the user. Claude is a tool, not a resource owner.

- **Scaffold new modules from existing patterns** — When creating a new Terraform module, copy `backend.tf`, `providers.tf`, and version constraints from the most recently created existing module in the same directory. Never write these boilerplate files from scratch — they contain project-specific patterns (backend config, assume role, provider versions) that must be consistent.

- **Always check the README or CI workflow for required `-var-file`** — Most deployment modules require explicit `-var-file` flags. Before running `terraform plan/apply`, check the module's README or the CI workflow YAML for the correct var-file path. Do not rely on defaults alone.
