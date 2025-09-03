# GitHub Actions Workflow Development Protocol

## MANDATORY for ALL workflow changes - no exceptions

### Core Requirements

#### 1. Act Testing Protocol

Every workflow change MUST be tested with `act` before implementation:

> **Note**: When AI assistants cannot execute `act` directly, provide the exact commands and explain the testing process that should be followed.

- Create isolated test workflow first
- Test with: `act -W .github/workflows/test.yaml --job jobname --container-architecture linux/amd64`
- Provide proof of successful testing with output (or instructions for user to execute)
- Apply to main workflow only after test passes
- Re-test main workflow with `act`
- Clean up test files

#### 2. Path Validation

All relative paths MUST be validated with actual commands:

- Test every `cd` path: `cd start/directory && ls -la target/path`
- Test every file reference: `cd start/directory && ls -la path/to/file.yaml`
- Document path relationships in comments
- No assumptions about directory structure

#### 3. Conditional Branch Coverage

Every `if:` statement MUST be tested:

- Create test event files for all conditional branches
- Test each branch with `act` using appropriate event files
- Example: `if: ${{ inputs.plan == 'true' }}` requires testing both `plan=true` and `plan=false`

#### 4. Working Directory Documentation

Always document working directory context:

```yaml
# ✅ Required format:
- working-directory: path/to/working/dir
  run: |
    # From: path/to/working/dir
    # To: path/to/target/dir
    # Relationship: ../target/dir
    cd ../target/dir
```

#### 5. Integration Testing

Test complete user journeys, not just isolated steps:

- Validate end-to-end workflows that users actually run
- Test both success and failure scenarios
- Ensure validation paths work the same as deployment paths

### Project-Specific Standards

#### Version Pinning

- Pin ALL GitHub Actions including actions/checkout
- Include version comments inline: `uses: action@hash # v4.2.2`
- Justify version choices when deviating from latest

### Forbidden Practices

- Never assume paths work without testing
- Never skip conditional branch testing
- Never submit workflow changes without `act` validation proof
- Never use relative paths without documentation

**Failure to follow this protocol results in broken production workflows and frustrated users.**

## General GitHub Actions Guidelines

### Workflow Structure

- Use reusable workflows or composite actions for repeatable pipelines
- Define minimal scopes for permissions: at job and workflow level
- Use secrets securely via GitHub Secrets or OIDC for cloud access
- Use matrix strategy to run tests/builds in parallel efficiently
- Cache dependencies (e.g., ~/.cache, ~/.poetry, ~/.npm) to speed up workflows

### Validation & Quality

- Validate workflows with actionlint or act locally
- Structure workflows clearly:
  - on: events (e.g., push, pull_request)
  - jobs: with named steps
  - env: for global environment setup
- Use if: guards to prevent unnecessary execution (e.g., if: github.ref == 'refs/heads/main')
- Use OIDC-based short-lived tokens for cloud access

### Workflow Patterns

- Use path-based change detection with dorny/paths-filter
- Implement matrix builds for multi-language/multi-service repositories
- Use concurrency groups to prevent overlapping deployments
- Employ self-hosted runners for resource-intensive tasks

## Project-Specific Workflow Preferences

### Workflow Organization

- Prefer using single-file GitHub workflow with separate jobs for simplicity in the GitHub UI
- Name recovery jobs as "app-recovery" instead of "regular-app-recovery"
- Prefer using GitHub composite actions in workflows instead of inline bash steps
- Call composite actions multiple times with different variables per run for modularity

### Command Behavior & Limitations

- Terraform plan commands should be allowed to finish fully without truncation or rerunning, since Terraform reports errors at the end
- In .github/workflows, use available functions like join and format; split and replace are not available
- Prefer not to use unverified third-party GitHub Actions when installing tools like the AWS CLI
- Versions specified in CI and workflows should align and use a single source of truth
