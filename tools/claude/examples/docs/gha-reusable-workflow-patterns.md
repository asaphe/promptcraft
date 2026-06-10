# Reusable Workflow & Composite Action Patterns

> **Scope:** examples from one team's reusable-workflows repo, distilled to patterns. The OIDC auth, lock recovery, and concurrency-group sections are universal-for-GHA. The deployment-specific patterns (scope-gated deployment, multi-tenant matrix, image tag resolution priority, wave-ordered Helm upgrades, notification routing, workspace-naming schema) are **opinionated examples** — illustrating the *shape* of the problem, not a recipe to copy. Adapt freely.

Each pattern below addresses a real operational concern. Each section flags whether the pattern itself is universal or example-specific.

## OIDC Authentication

Every job that touches AWS uses an OIDC `setup-aws` step with `id-token: write` permission. No long-lived credentials.

```yaml
permissions:
  id-token: write
  contents: read

steps:
  - uses: ./.github/actions/setup-aws
    with:
      aws_role_arn: ${{ inputs.aws_role_arn }}
      aws_region: ${{ inputs.aws_region }}
```

Session name defaults to `gha-{run_id}-{job}`. ECR login is bundled by default in many setups (`skip_ecr_login: "true"` to opt out).

## Cross-Repo Checkout

Ops workflows in a reusable-workflows repo check out themselves and the caller repo whose code they operate on:

```yaml
- uses: actions/checkout@<sha>
  with:
    path: gha    # the reusable-workflows repo, this side

- uses: actions/checkout@<sha>
  with:
    repository: ${{ inputs.target_repo }}    # e.g., <your-org>/infrastructure
    token: ${{ steps.app_token.outputs.token }}
    path: target
    sparse-checkout: |
      terraform
```

All action references then use `./gha/.github/actions/...`. A GitHub App token (created via `actions/create-github-app-token`) provides cross-repo access; the standard `GITHUB_TOKEN` does not.

## Scope-Gated Deployment

Map a single `scope` input string to boolean outputs:

```yaml
# resolve_scope job maps strings like 'app', 'app-and-infra', 'full' →
# deploy_infrastructure, deploy_rds, deploy_db_config booleans
```

Downstream jobs gate on the resolved booleans:

```yaml
deploy_rds:
  needs: resolve_scope
  if: needs.resolve_scope.outputs.deploy_rds == 'true'
```

## Skip-Cascade Gates for Conditional Jobs

**Universal-for-GHA.** Any conditional job (like the scope-gated jobs above, or a "create resource only if absent" job) poisons its entire downstream `needs:` chain: GitHub's implicit `success()` gate evaluates the **transitive** ancestry, so one skipped ancestor auto-skips every descendant — even those whose direct dependencies succeeded.

```yaml
# ecr_create is skipped on the common repo-already-exists path
build:
  needs: [ecr_check, ecr_create]
  if: ${{ !cancelled() && needs.ecr_check.result == 'success' && (needs.ecr_create.result == 'success' || needs.ecr_create.result == 'skipped') }}

# push_manifest only directly needs build — but the skipped ecr_create
# propagates through build's ancestry and auto-skips this job too
push_manifest:
  needs: build
  if: ${{ !cancelled() && needs.build.result == 'success' }}
```

- `!cancelled()` is the status-check function that stops GitHub from auto-skipping the job past a skipped ancestor; `always()` is deliberately not used — it would also run the job on cancellation.
- The explicit `needs.<dep>.result == 'success'` clauses keep the job gated on real success, replacing the implicit gate the override disabled.
- **Every future job added downstream of the conditional job must carry the same override** — otherwise it silently never runs. This is lintable: a CI script can fail the build when a job relying on the implicit `success()` gate has a conditionally-skippable ancestor, with an inline marker comment to declare intentional cascade-skips.
- Related verification gotcha: branch protection counts a `skipped` required check as passing — a merge-green workflow does not prove the gated jobs executed. Enumerate job conclusions via `gh api .../actions/runs/{id}/jobs` before trusting green.

## Multi-Tenant Tenant Matrix

MT workflows dynamically build JSON matrices at runtime:

1. Tenant list from a discovery store (SSM Parameter Store, ConfigMap, etc.)
2. Section / module list from directory scanning
3. Cartesian product (tenant × section) built with `jq`

```yaml
strategy:
  fail-fast: false
  matrix:
    include: ${{ fromJson(needs.discover.outputs.tenant_matrix) }}
concurrency:
  group: tf-{module}-${{ matrix.tenant }}-${{ matrix.section }}
  cancel-in-progress: false
```

## Concurrency Groups

**Terraform / state-mutating jobs:** Named groups with `cancel-in-progress: false` to serialize state operations without cancellation.

**Workflow-level:** Prevents concurrent provision / cleanup for the same deployment:

```yaml
concurrency:
  group: mt-provision-${{ inputs.deployment_name }}-${{ inputs.environment }}
  cancel-in-progress: false
```

## Lock Recovery on Cancel

Every `terraform-plan-apply` step is followed by a `terraform-force-unlock` step:

```yaml
- uses: ./.github/actions/terraform-force-unlock
  if: steps.apply.outcome == 'cancelled' || cancelled()
```

The force-unlock action uses a bogus lock-ID probe to detect existing locks before clearing them.

## Provider-Specific Auto-Recovery

Inside `terraform-plan-apply`, apply output is teed to `/tmp/terraform_apply_output.log`. If exit code is nonzero and output contains a known transient pattern (e.g., `Provider produced inconsistent result`, hash-mismatch errors), auto-run `terraform refresh` then re-plan and re-apply. Bound retries to 1–2 to avoid masking persistent failures.

## Image Tag Resolution

A reusable `resolve-image-tag` action implements priority: manual input → git tag → branch name (staging only; prod fails with no explicit tag). Always validate the image exists in the registry before downstream jobs consume it.

## GitHub App Token for Environment Management

`actions/create-github-app-token` creates tokens for:

- Dynamic GitHub Environment creation via REST API
- Cross-repo checkout of `infrastructure` and application repos
- User email lookup for direct-message routing in notifications

## Provider Mirror (Self-Hosted Runners)

Self-hosted runners can pre-bake a Terraform provider mirror at a known path (e.g., `/opt/terraform-mirror`). A `setup-terraform` step generates `~/.terraformrc` pointing to it. Custom provider forks can be synced from object storage at runner image build time.

## Notification Pattern

All deployment workflows end with a `notify_workflow_result` job using `if: always()`:

1. Resolve the triggering user's email via GitHub GraphQL
2. Look up the user in your messaging system (Slack `users.lookupByEmail`, etc.)
3. DM the user with workflow status

Channel notifications use a per-team / per-env naming convention (e.g., `{team}-deployments-{env}`).

## Terraform Workspace Naming

- **Single-tenant:** `{env}_{deployment}_{module}` or `{env}_{cluster}_{deployment}_{region}`
- **Multi-tenant per-tenant:** `{env_prefix}-{deployment}_{tenant}_{section}_{region}`
- **Multi-tenant shared:** `{env_prefix}-{deployment}_{app}_{region}`

## Wave-Ordered Helm Upgrades

A `helm-upgrade-tenant-apps` action deploys all apps in parallel first, then dependent apps wait for upstream completion. Stuck releases (Helm `pending-*` / `failed` states) are automatically rolled back before retry — see the `helm-rollback-after-keep-history` caveat: never use `helm uninstall --keep-history` as a safety net; the release becomes stuck in `pending-rollback` and `helm rollback` cannot recover it.
