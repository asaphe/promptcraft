# Composite Action & Workflow Specification

Foundational rules for GitHub Actions workflows and composite actions. Read this before creating or modifying any workflow or action.

## 1. Naming Conventions

### Identifiers

Use `[a-zA-Z0-9_]*` for ALL identifiers:

- Job names
- Step IDs
- Input names
- Output names

**No hyphens.** GitHub expressions treat `-` as the minus operator, causing silent evaluation bugs.

```yaml
# CORRECT
steps:
  - id: resolve_scope
    # ...
jobs:
  deploy_helm:
    # ...

# WRONG — hyphens cause expression bugs
steps:
  - id: resolve-scope  # github.steps.resolve-scope → subtraction
```

### Files

- Workflow files: `kebab-case.yaml` (e.g., `deploy-stg.yaml`, `rds-config.yaml`)
- Action directories: `kebab-case/` (e.g., `setup-aws/`, `terraform-plan-apply/`)
- Shell scripts: `kebab-case.sh` or `snake_case.py`

## 2. External Action Pinning

Pin ALL external actions to commit SHAs with a version comment:

```yaml
- uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd # v6.0.2
```

**Verification:**

```bash
# Use the tags endpoint, not git/ref/tags — annotated tags return the
# tag object SHA from git/ref/tags, not the commit SHA actions pin to.
gh api repos/{owner}/{repo}/tags --paginate \
  --jq '.[] | select(.name == "{tag}") | .commit.sha'
```

Never use tag references (`@v4`), branch references (`@main`), or unpinned versions for third-party actions. Internal reusables may use `@main` if the trust boundary is bounded by org membership.

## 3. Composite Action Rules

### Shell

Every `run` step in a composite action MUST have `shell: bash` — composite actions don't inherit shell from the caller.

```yaml
steps:
  - run: |
      set -euo pipefail
      echo "Hello"
    shell: bash
```

### Bash Safety

Every bash `run` step should start with `set -euo pipefail`.

With `shell: bash`, GHA already runs with `bash --noprofile --norc -eo pipefail {0}`, providing `-e` and `-o pipefail`. The `set -u` (treat unset variables as errors) is NOT included by default. Add it explicitly when:

- The step references variables that could be unset
- The step uses `$@` / `$*` expansion without defaults

For steps where all variables are guaranteed set (e.g., from `${{ inputs.* }}`), `set -euo pipefail` is still the standard practice for consistency.

### Inputs

Use `${{ inputs.* }}` to reference inputs in composite actions. NOT `${{ github.event.inputs.* }}` (which only works in `workflow_dispatch`).

### Outputs

Declare outputs explicitly and set via `$GITHUB_OUTPUT`:

```yaml
outputs:
  result:
    description: "The computed result"
    value: ${{ steps.compute.outputs.result }}

steps:
  - id: compute
    run: echo "result=value" >> "$GITHUB_OUTPUT"
    shell: bash
```

### Security

Never interpolate user-controlled values directly into `run:` steps:

```yaml
# WRONG — injection risk
- run: echo "Processing ${{ github.event.pull_request.title }}"
  shell: bash

# CORRECT — use environment variable
- run: echo "Processing $PR_TITLE"
  shell: bash
  env:
    PR_TITLE: ${{ github.event.pull_request.title }}
```

## 4. Workflow Rules

### Permissions

Every workflow MUST have an explicit `permissions` block at the workflow level. Use minimal permissions:

```yaml
permissions:
  id-token: write    # Only if OIDC is used
  contents: read     # Default for checkout
  pull-requests: write  # Only if posting PR comments
```

Never use `write-all` or omit the block entirely.

### Concurrency

Terraform jobs (and any state-mutating job) MUST have concurrency groups with `cancel-in-progress: false`:

```yaml
concurrency:
  group: terraform-{module}-${{ inputs.deployment_name }}-${{ inputs.region }}
  cancel-in-progress: false
```

CI/test workflows CAN use `cancel-in-progress: true`:

```yaml
concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true
```

### Matrix Strategies

Multi-tenant matrix jobs MUST use `fail-fast: false` so one tenant's failure doesn't cancel siblings:

```yaml
strategy:
  fail-fast: false
  matrix:
    include: ${{ fromJson(needs.discover.outputs.tenant_matrix) }}
```

### Notification / Cleanup Jobs

Jobs that must run regardless of upstream failures:

```yaml
notify:
  if: always()
  needs: [deploy, verify]
```

### Lock Recovery

Every Terraform apply step should be followed by a force-unlock guard:

```yaml
- uses: ./.github/actions/terraform-force-unlock
  if: steps.apply.outcome == 'cancelled' || cancelled()
```

## 5. Secret Handling

### Masking

Mask sensitive values before any echo/log operation:

```yaml
- run: |
    SECRET=$(aws secretsmanager get-secret-value --secret-id my/secret --query SecretString --output text)
    echo "::add-mask::$SECRET"
    echo "secret=$SECRET" >> "$GITHUB_OUTPUT"
  shell: bash
```

### No Hardcoded Credentials

- AWS account IDs: pass as inputs or derive from OIDC role
- API keys: fetch from Secrets Manager at runtime
- Tokens: use GitHub App token generation

## 6. Error Diagnostics

Composite actions should include diagnostic output for common failure modes:

```yaml
- run: |
    set -euo pipefail
    if ! terraform apply -auto-approve tfplan; then
      echo "::error::Terraform apply failed"
      # Check for known patterns
      if grep -q "EntityAlreadyExists" /tmp/terraform_apply_output.log; then
        echo "::warning::Resource already exists — may need import"
      fi
      exit 1
    fi
  shell: bash
```

## 7. Validation Checklist

Before submitting changes to workflows or actions:

1. [ ] `actionlint` passes on all modified workflow files
2. [ ] `shellcheck` passes on all modified shell scripts
3. [ ] Step/job IDs use `snake_case` only (no hyphens)
4. [ ] All external actions pinned to commit SHAs with version comment
5. [ ] `shell: bash` on all composite action `run` steps
6. [ ] `set -euo pipefail` on all bash steps
7. [ ] `permissions` block present and minimal on workflows
8. [ ] Concurrency groups on Terraform / state-mutating jobs
9. [ ] Conditional jobs tested with both true/false paths
10. [ ] No secrets echoed without `::add-mask::`
11. [ ] Cross-repo action paths match directory structure
12. [ ] Input/output contracts match between callers and actions
