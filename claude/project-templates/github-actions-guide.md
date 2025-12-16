# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with GitHub Actions workflows in this repository.

---

## GITHUB ACTIONS WORKFLOW DEVELOPMENT GUIDE

## Mandatory Workflow Development Protocol

**CRITICAL**: These requirements are NON-NEGOTIABLE for ALL workflow changes.

### 1. Act Testing Requirement

**ALWAYS test workflows with `act` before implementation:**

```bash
# Create isolated test workflow first
act -W .github/workflows/test-workflow.yml --job test_job --container-architecture linux/amd64

# Test with specific events
act push --eventpath .github/test-events/push-main.json

# Test workflow dispatch with inputs
act workflow_dispatch -W .github/workflows/deploy.yml \
  --input environment=staging \
  --input tenant=acme
```

**Testing Checklist:**

- ✓ Create test workflow before modifying production workflows
- ✓ Test ALL conditional branches with different event files
- ✓ Verify path operations with actual directory structures
- ✓ Provide successful test evidence or detailed instructions
- ✓ Only apply to production workflow after validation

### 2. Path Validation Protocol

**NEVER assume directory structure - always verify:**

```bash
# Verify paths before using in workflows
cd /repo/root && ls -la python/<module>/src
cd /repo/root && ls -la typescript/apps/<app>/dist

# Document working directory in workflow comments
# Working directory: /repo/root
# Target: python/<module>/src
```

**Path Documentation Standard:**

```yaml
- name: Build Python Package
  # From: /repo/root
  # To: python/<module>
  # Builds wheel: dist/ingestion-*.whl
  working-directory: python/<module>
  run: poetry build
```

### 3. Conditional Branch Coverage

**Test EVERY conditional with actual event files:**

```yaml
# Example conditional
if: github.event_name == 'push' && github.ref == 'refs/heads/main'
```

**Required test cases:**

1. Push to main → condition true
2. Push to feature branch → condition false
3. Pull request → condition false

**Event file example (`.github/test-events/push-main.json`):**

```json
{
  "ref": "refs/heads/main",
  "repository": {
    "name": "<repo-name>",
    "owner": {"login": "<organization>"}
  }
}
```

### 4. Naming Safety Protocol

**CRITICAL**: Use only safe, portable identifiers.

**Valid Characters:** `a-zA-Z0-9_` (alphanumeric + underscore)

**Examples:**

```yaml
# ✓ CORRECT
jobs:
  build_api:
    outputs:
      build_artifact: ${{ steps.build.outputs.path }}

# ✗ INCORRECT - will fail
jobs:
  build-api:  # hyphen breaks expressions
    outputs:
      build-artifact: ${{ steps.build.outputs.path }}
```

**Exception:** File names and workflow names CAN use hyphens (e.g., `build-and-deploy.yml`)

### 5. Version Pinning

**Pin ALL actions to commit SHAs with version comments:**

```yaml
steps:
  - uses: actions/checkout@b4ffde65f46336ab88eb53be808477a3936bae11 # v4.1.1
  - uses: actions/setup-node@60edb5dd545a775178f52524783378180af0d1f8 # v4.0.2
  - uses: actions/setup-python@0a5c61591373683505ea898e09a3ea4f39ef2b9c # v5.0.0
```

---

## Project-Specific Patterns

### Change Detection

We use `dorny/paths-filter` to detect changes by language/service:

```yaml
detect-changes:
  outputs:
    python_<module>: ${{ steps.filter.outputs.python_<module> }}
    typescript_<app>: ${{ steps.filter.outputs.typescript_<app> }}
  steps:
    - uses: dorny/paths-filter@v3
      id: filter
      with:
        filters: |
          python_<module>:
            - 'python/<module>/**'
            - 'python/common/**'
          typescript_<app>:
            - 'typescript/apps/<app>/**'
            - 'typescript/packages/**'
```

**Pattern:** Only build/test changed services for efficiency.

### Container Build Strategy

**ECR Repository Management:**

- Auto-create repositories via Terraform during build
- Use consistent tagging: `branch`, `PR number`, `SHA`, semantic versions
- Multi-stage builds with BuildKit caching (`type=gha`)

**Build Matrix Example:**

```yaml
strategy:
  matrix:
    include:
      - service: <service-name>
        context: python/<service_name>
        dockerfile: python/<service_name>/Dockerfile
        changed: ${{ needs.detect-changes.outputs.python_<module> }}
```

### Deployment Workflows

**Manual Dispatch Pattern:**

```yaml
on:
  workflow_dispatch:
    inputs:
      environment:
        type: choice
        options: [staging, production]
        required: true
      tenant:
        type: string
        required: true
      service:
        type: string
        required: true
```

**Terraform Workflow:**

1. Select/create workspace: `{env}_{tenant}-{service}`
2. Run `terraform plan` with review
3. Require approval for production
4. Apply with summary output

### Security Integration

**Gitleaks Configuration:**

- Custom patterns in `devops/gitleaks.toml`
- Exemptions in `.gitleaksignore`
- Run on all PRs and pushes

**Vulnerability Scanning:**

- Thresholds: critical: 1, high: 1, medium: 3
- Scan containers before deployment
- Use Hadolint for Dockerfile validation

---

## Testing & Quality Gates

### Required Linting

```bash
# Run before committing workflow changes
actionlint .github/workflows/*.yml
yamllint .github/workflows/
shellcheck .github/scripts/*.sh
```

### Test Execution Patterns

**Python Tests:**

```yaml
- name: Run Tests
  run: |
    cd python
    poetry run pytest ${{ matrix.module }}/tests -v
```

**TypeScript Tests:**

```yaml
- name: Run Tests
  run: |
    cd typescript
    pnpm test --filter=${{ matrix.package }}
```

**E2E Tests:**

```yaml
- name: E2E Tests
  run: |
    cd typescript/apps/<app>
    pnpm test:e2e
```

### Dependency Caching

**Python (Poetry):**

```yaml
- uses: actions/cache@v4
  with:
    path: ~/.cache/pypoetry
    key: poetry-${{ hashFiles('python/poetry.lock') }}
```

**TypeScript (pnpm):**

```yaml
- uses: pnpm/action-setup@v2
  with:
    version: 10
- uses: actions/setup-node@v4
  with:
    cache: 'pnpm'
    cache-dependency-path: typescript/pnpm-lock.yaml
```

---

## AWS Integration

### OIDC Authentication

```yaml
- name: Configure AWS Credentials
  uses: aws-actions/configure-aws-credentials@v4
  with:
    role-to-assume: arn:aws:iam::<AWS_ACCOUNT_ID>:role/github-actions
    aws-region: us-east-1
```

### ECR Login

```yaml
- name: Login to Amazon ECR
  uses: aws-actions/amazon-ecr-login@v2
  with:
    registry: <AWS_ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com
```

---

## Common Workflow Templates

### Linting Workflow

```yaml
name: Lint
on: [pull_request, push]

jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Run actionlint
        run: |
          bash <(curl https://raw.githubusercontent.com/rhysd/actionlint/main/scripts/download-actionlint.bash)
          ./actionlint

      - name: Run yamllint
        run: yamllint .github/workflows/
```

### Container Build Workflow

```yaml
name: Build Container
on:
  push:
    branches: [main]
  pull_request:

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Build and Push
        uses: docker/build-push-action@v5
        with:
          context: python/<service_name>
          file: python/<service_name>/Dockerfile
          push: ${{ github.event_name == 'push' }}
          tags: |
            <AWS_ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/<service-name>:${{ github.sha }}
          cache-from: type=gha
          cache-to: type=gha,mode=max
```

---

## Troubleshooting

### Common Issues

**1. Path not found errors:**

- Always verify paths with `cd && ls -la` before use
- Check `working-directory` is correct
- Verify files exist in repository

**2. Expression evaluation errors:**

- Check for hyphens in identifiers (use underscores)
- Verify conditional syntax with test events
- Use `${{ }}` for all expressions

**3. Cache misses:**

- Verify cache key includes correct hash files
- Check cache path is correct for tool
- Use `restore-keys` for fallback

**4. Permission denied:**

- Check GITHUB_TOKEN permissions in workflow
- Verify IAM role has required AWS permissions
- Ensure files have execute permissions if needed

---

## Resources

- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [Act - Local Testing](https://github.com/nektos/act)
- [Actionlint - Workflow Linter](https://github.com/rhysd/actionlint)
- [Our Workflow Examples](.github/workflows/)

---

**Model**: Claude Sonnet 4.5
**Confidence**: High - Based on existing CLAUDE.md specification and project-specific patterns
