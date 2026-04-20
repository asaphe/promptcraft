# CI/CD Specification

RFC-style specification for CI/CD standards. This is the authoritative source — when existing code violates this spec, the spec wins.

## Iron Rules

These rules apply to ALL CI/CD and infrastructure files. No exceptions.

1. **Pin all versions** — Actions to SHA, providers to version, base images to tag. Never `latest`.
2. **Test before merge** — All workflows must be tested with `act` or equivalent before merging.
3. **Path validation** — Every workflow that runs on push/PR must have path filters.
4. **Naming convention** — Workflow files: `snake_case.yaml`. Job/step IDs: `snake_case`.

## GitHub Actions Standards

### Action Pinning

```yaml
# CORRECT: pinned to commit SHA with version comment
- uses: actions/checkout@<sha>  # v4.1.0

# WRONG: pinned to tag (mutable)
- uses: actions/checkout@v4
```

### Bash Steps

```yaml
# CORRECT: explicit shell and error handling
- name: Run build
  shell: bash
  run: |
    set -euo pipefail
    make build

# WRONG: no shell specified, no error handling
- name: Run build
  run: make build
```

### Concurrency

Every workflow must have a concurrency group to prevent duplicate runs:

```yaml
concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true
```

### Permissions

Every workflow must declare minimal permissions:

```yaml
permissions:
  contents: read
  id-token: write  # only if OIDC needed
```

## Terraform Standards

### Required Files

Every module must have: `backend.tf`, `providers.tf`, `main.tf`, `variables.tf`, `outputs.tf`, `data.tf`, `.terraform-version`, `README.md`.

### Provider Lock

All modules must have `.terraform.lock.hcl` with checksums for all 4 platforms:

```bash
terraform providers lock \
  -platform=darwin_amd64 \
  -platform=darwin_arm64 \
  -platform=linux_amd64 \
  -platform=linux_arm64
```

## Docker Standards

- Multi-stage builds required
- Base images pinned to specific version
- `hadolint` must pass with no warnings
- Non-root USER directive required
- No secrets in build args or layers

## Shell Script Standards

- `set -euo pipefail` at top of every script
- `shellcheck` must pass
- All variables quoted (`"$var"` not `$var`)
