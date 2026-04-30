---
name: new-gh-action
description: Scaffold a new GitHub Actions composite action or workflow. Usage - /new-gh-action [name]
user-invocable: true
allowed-tools: Bash(actionlint *), Bash(gh *), Read, Write, Edit, Glob, Grep, AskUserQuestion
argument-hint: "[action-or-workflow-name]"
---

# Scaffold New GitHub Action

Create a new composite action or workflow following the conventions in `.claude/docs/composite-action-spec.md`.

## Steps

### 1. Determine type

Ask the user: **Composite action** or **Workflow**?

If `$ARGUMENTS` is provided, use it as the name.

### 2a. Composite Action

Ask the user:

1. **Name**: kebab-case (e.g., `setup-database`, `validate-schema`)
2. **Purpose**: One-line description
3. **Inputs**: List of inputs with descriptions and whether required
4. **Outputs**: List of outputs (if any)

Create `.github/actions/{name}/action.yml`:

```yaml
name: "{Display Name}"
description: "{Purpose}"

inputs:
  {input_name}:
    description: "{Description}"
    required: {true|false}
    default: "{default if optional}"

outputs:
  {output_name}:
    description: "{Description}"
    value: ${{ steps.{step_id}.outputs.{output_name} }}

runs:
  using: "composite"
  steps:
    - name: {Step description}
      id: {step_id}
      shell: bash
      run: |
        set -euo pipefail
        # TODO: implement
```

**Rules applied automatically:**

- `shell: bash` on every run step
- `set -euo pipefail` at the start of every bash block
- snake_case for all step IDs (no hyphens — GHA expressions parse `-` as minus)
- External actions pinned to commit SHAs (look up SHAs if needed)

### 2b. Workflow

Ask the user:

1. **Name**: kebab-case filename (e.g., `deploy-lambda.yaml`)
2. **Trigger**: push / PR (with paths), manual dispatch, schedule, or combination
3. **Purpose**: What the workflow does
4. **Needs change detection?**: If yes, include `dorny/paths-filter` job

For **push / PR workflows**, use the standard template with:

- Change detection via `dorny/paths-filter@<sha> # vX.Y.Z`
- Concurrency group with `cancel-in-progress: true` (CI / test) or `false` (Terraform / state-mutating)
- Minimal permissions

For **manual dispatch workflows**, use:

- `workflow_dispatch` with typed inputs
- Choice inputs for environment / deployment selection
- Boolean for plan-only mode
- AWS OIDC setup via your `setup-aws` composite action

Create `.github/workflows/{name}`:

```yaml
name: {Display Name}

on:
  {trigger config}

concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

permissions:
  contents: read
  id-token: write

jobs:
  {job_name}:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@<sha> # v4.x.y
      # TODO: implement
```

**Rules applied automatically:**

- snake_case for job names and step IDs
- All actions pinned to commit SHAs with version comments
- Concurrency group to prevent parallel runs
- Minimal permissions declared

### 3. Validate

Run actionlint on the created file:

```bash
actionlint .github/workflows/{file} 2>&1 || true
```

For composite actions, validate the YAML structure is correct.

### 4. Summary

Tell the user:

- File created at the path
- Remind them to:
  - Implement the TODO sections
  - Pin any additional external actions to commit SHAs
  - Test with `act` before pushing (see your CI/CD spec)
  - Run `actionlint` after making changes

## Reference

- `.claude/docs/composite-action-spec.md` — full spec
- `.claude/docs/gha-reusable-workflow-patterns.md` — recurring patterns (OIDC, cross-repo checkout, scope-gated deployment, etc.)
- `.claude/rules/devops/gha-workflow-authoring.md` — gotchas
