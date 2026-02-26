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

#### 6. Parameter Renaming Protocol

**CRITICAL**: When renaming workflow inputs, parameters, or variables in GitHub Actions, you MUST update multiple locations.

**The GitHub Actions Quirk**: GitHub Actions have a two-tier system:

1. **Workflow files** (`.github/workflows/*.yaml`) - where parameters are **PASSED**
2. **Action files** (`.github/actions/*/action.yml`) - where parameters are **DEFINED** as inputs

**A single parameter rename requires changes in BOTH locations!**

##### The Complete Rename Process

###### Step 1: Search BOTH Callers AND Definitions

```bash
# Search across ALL GitHub Actions files
grep -r "parameter_name" .github/ --include="*.yml" --include="*.yaml"
```

You must check:

- ✅ **Workflow files** (`.github/workflows/*.yaml`) - where parameters are PASSED
- ✅ **Action files** (`.github/actions/*/action.yml`) - where parameters are DEFINED as inputs
- ✅ **Reusable workflows** - which may also define/use the parameter
- ✅ **Documentation** - references to the parameter

###### Step 2: Update ALL Locations

Update the parameter name in:

1. **Action input definitions** (`.github/actions/*/action.yml`):

   ```yaml
   inputs:
     old_parameter_name:  # ← Change this
       description: "..."
   ```

2. **Action input references** within the same action file:

   ```yaml
   run: |
     echo "${{ inputs.old_parameter_name }}"  # ← Change this
   ```

3. **Workflow files** that call the action:

   ```yaml
   - uses: ./.github/actions/my-action
     with:
       old_parameter_name: value  # ← Change this
   ```

4. **Workflow inputs** (if applicable):

   ```yaml
   on:
     workflow_dispatch:
       inputs:
         old_parameter_name:  # ← Change this
   ```

###### Step 3: Verify ZERO Old References Remain

```bash
# This should return NOTHING:
grep -r "old_parameter_name" .github/

# This should show all the NEW references:
grep -r "new_parameter_name" .github/
```

##### Common Mistake

**Mistake**: Updating the workflow files but forgetting the action definition file.

**Result**: The workflow passes `new_parameter_name`, but the action expects `old_parameter_name`, resulting in an empty value.

**Example Error**:

```text
Warning: Unexpected input(s) 'new_parameter_name', valid inputs are ['old_parameter_name', ...]
```

##### Quick Reference Checklist

- [ ] Found ALL occurrences in `.github/` directory
- [ ] Updated action input definitions (`.github/actions/*/action.yml`)
- [ ] Updated action input references within action files
- [ ] Updated workflow files that call the action
- [ ] Updated workflow input definitions (if applicable)
- [ ] Updated any reusable workflow definitions
- [ ] Updated documentation
- [ ] Verified old parameter name returns ZERO grep results
- [ ] Ran workflow syntax validation

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

#### Mandatory Linting & Validation Protocol

**CRITICAL**: Before committing ANY workflow or Dockerfile changes, you MUST run appropriate linting and validation tools.

##### GitHub Actions Workflow Validation

1. **actionlint** - Validates workflow syntax and best practices:

   ```bash
   actionlint .github/workflows/workflow-name.yaml
   ```

   - Fix all errors (except expected self-hosted runner label warnings)
   - Common issues: invalid context usage (e.g., `secrets` in matrix `env`), syntax errors, undefined variables

2. **YAML Syntax Validation** - Verify YAML is well-formed:

   ```bash
   yq eval 'true' .github/workflows/workflow-name.yaml
   ```

   - Ensures YAML parsing works correctly
   - Catches indentation and syntax errors

3. **Command Output Verification**:
   - **ALWAYS check command output** - Don't guess at issues
   - Read error messages carefully before making assumptions
   - Verify actual error vs. expected behavior
   - Example: If `act` fails, check if it's YAML syntax, Docker socket, or workflow logic

##### Dockerfile Validation

1. **hadolint** - Lints Dockerfiles for best practices:

   ```bash
   hadolint path/to/Dockerfile
   ```

   - Must pass with zero errors
   - Checks for security issues, best practices, and common mistakes
   - Run on all Dockerfiles before committing

2. **Multi-stage Build Validation**:
   - Verify ARG declarations are in correct stages
   - Ensure ARGs are re-declared in stages where needed
   - Check ENV variables are set in appropriate stages
   - Validate build-args are passed correctly from workflow

##### Build-Args & Conditional Syntax Validation

When using conditional build-args in workflows:

1. **Always use `|| ''` fallback** to prevent `false` values:

   ```yaml
   # ✅ Correct
   ${{ matrix.language == 'typescript' && 'NODE_ENV=production' || '' }}

   # ❌ Wrong - returns 'false' string when condition is false
   ${{ matrix.language == 'typescript' && 'NODE_ENV=production' }}
   ```

2. **Test conditional evaluation**:
   - Verify conditionals return expected values for all matrix combinations
   - Use `act` or test workflows to validate actual output
   - Check that empty strings are handled correctly by Docker build action

3. **Secrets Context Limitations**:
   - `secrets` context is NOT available in matrix `env` definitions
   - Pass secrets via build-args or step-level `env` instead
   - Example: Use `build-args` for Docker secrets, not matrix `env`

##### Validation Checklist

Before committing workflow/Dockerfile changes:

- [ ] `actionlint` passes (or only expected warnings)
- [ ] `yq` validates YAML syntax
- [ ] `hadolint` passes for all Dockerfiles
- [ ] All conditional expressions use `|| ''` fallback
- [ ] No `secrets` context in matrix definitions
- [ ] Build-args tested with `act` or validated manually
- [ ] Command outputs checked and verified (not guessed)
- [ ] ARG/ENV properly scoped in Dockerfile stages

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
