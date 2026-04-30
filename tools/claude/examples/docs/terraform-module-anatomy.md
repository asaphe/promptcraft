# Terraform Module Anatomy

Conventions for a reusable Terraform module library — the kind consumed by root configs in a separate repo via a module registry (S3, Terraform Registry, git tags).

## Module Anatomy

Each module directory MUST contain:

| File | Purpose |
|------|---------|
| `main.tf` | Primary resources |
| `variables.tf` | All input variables with `type` and `description` |
| `outputs.tf` | All outputs with `description` |
| `data.tf` | ALL data sources (never inline in `main.tf`) |
| `locals.tf` | Local values (if needed) |
| `versions.tf` | `required_providers` for non-HashiCorp providers only |
| `README.md` | Usage examples, inputs / outputs summary |

Additional resource-specific files (e.g., `security_groups.tf`, `secrets.tf`) are encouraged when a module has many resources — keep `main.tf` focused on the primary resource.

## What does NOT belong in modules

- `backend.tf` / `providers.tf` / `.terraform-version` — these belong in root configs, not reusable modules. A module that defines a backend or provider can't be composed.
- `terraform { required_version }` — version pinning is handled by `.terraform-version` in root configs.
- Hardcoded account IDs, ARNs, or environment-specific values — use variables.

## Code Standards

- `terraform fmt` must pass — enforce in CI
- `tflint` must pass with a repo-level `.tflint.hcl` config
- Every variable must have `type` and `description`
- Every output must have `description`
- Use `this` for the main / primary resource name
- Multiple related resources get descriptive names (`app_server`, `worker`)
- Prefer data sources over hardcoded values
- Follow DRY — extract repeated patterns into child modules

## Naming Conventions

- Module directories: `provider/service` (e.g., `aws/s3`, `databricks/tenant`)
- Nested modules: `provider/service/submodule` (e.g., `aws/eks/cluster`, `aws/eks/addons`)
- File names reflect purpose: `main.tf` for primary resource, descriptive names for secondary resources

## CI/CD

- **Lint workflow**: runs `terraform fmt -check` and `tflint` per changed module on PRs
- **Publish workflow**: packages and uploads modules to the registry on merge to `main`
- Module discovery is typically automatic — any directory containing `.tf` files is detected as a module root

## Versioning

Modules are independently versioned using semantic versioning derived from conventional commits since the last git tag:

- `feat:` → minor bump
- `fix:` / `refactor:` / `chore:` / `docs:` → patch bump
- `BREAKING CHANGE:` or `feat!:` → major bump

Conventions:

- Git tags use the format `{module-path}/vX.Y.Z` (e.g., `aws/s3/v1.2.0`)
- Published versions are immutable — registry keys are never overwritten
- Consumers pin to explicit versions; upgrades are opt-in

## Consumer Context

When root configs use `terraform_remote_state` to chain outputs between modules, treat outputs as a public API:

- Never remove an output without checking downstream consumers
- Passthrough outputs (echoing input variables) are intentional — they enable `terraform_remote_state` chains
- New outputs should be added when downstream modules need access to computed values
