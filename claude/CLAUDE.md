# CLAUDE CODE SPECIFICATION (RFC-STYLE)

**Version:** 1.1
**Last Updated:** 2025-12-10
**Document Type:** Canonical AI Enforcement Specification
**Purpose:** Define deterministic, exhaustive, machine-enforceable rules governing workflow development, testing, validation, naming, execution, and behavioral constraints for AI systems modifying GitHub Actions, Dockerfiles, Terraform, and supporting infrastructure.

---

**ALWAYS SPECIFY WHICH MODEL GAVE THE ANSWER AND THE CONFIDENCE LEVEL**

**DO NOT LEAVE OBVIOUS COMMENTS IN THE CODE**

## Quick Reference Summary

**Critical Requirements (Non-Negotiable):**

1. **Testing:** Generate act commands and test workflows for all modifications
2. **Path Validation:** Verify every path with explicit commands before use
3. **Naming:** Use only `[a-zA-Z0-9_]*` for identifiers (no hyphens in job names, inputs, outputs)
4. **Version Pinning:** Pin all actions to commit SHAs with version comments
5. **Linting:** Validate with actionlint, hadolint, shellcheck before completion
6. **Conditionals:** Test ALL branches with event files
7. **Parameter Renames:** Update ALL references and validate with grep

**Key Anti-Patterns to Avoid:**

- ✗ Using hyphens in job/step identifiers (use underscores instead)
- ✗ Assuming directory structure without verification
- ✗ Using `latest` tags for base images
- ✗ Incomplete parameter renames
- ✗ Untested conditional branches
- ✗ Including AI attribution in code or commits

---

# 1.0 CANONICAL FRAMEWORK

## 1.1 Scope

This specification applies to all AI-generated modifications to:

- GitHub Actions workflows
- Composite actions
- Dockerfiles
- Terraform infrastructure code
- Multi-language code used within CI/CD workflows
- Path references, conditionals, parameters, and validation logic

## 1.2 Enforcement Semantics

All MUST, SHALL, and REQUIRED terms indicate absolute requirements.
All SHOULD indicates strong recommendation.
AI MUST treat all CRITICAL rules as non-negotiable.

## 1.3 Rule Classes

- **CRITICAL:** Violating this causes workflow failure → AI MUST NOT produce violating output.
- **HIGH:** Strong recommendation → AI SHOULD follow.
- **MEDIUM:** Guidelines that improve maintainability.

---

# 2.0 IRON RULES (CRITICAL)

## 2.1 Act Testing Requirement

AI MUST:

1. Generate an isolated test workflow for any workflow modification.
2. Generate `act` commands to execute the test job.
3. Validate ALL branches of conditionals.
4. Provide instructions when `act` is not compatible.

**Example:**

```yaml
# test-workflow.yml
name: Test Build Job
on: push
jobs:
  test_build:
    runs-on: ubuntu-latest
    steps:
      - run: echo "Testing build logic"
```

**Act Command:**

```bash
act -W .github/workflows/test-workflow.yml --job test_build --container-architecture linux/amd64
```

## 2.2 Path Validation Protocol

AI MUST:

- Verify every path using explicit `cd` + `ls -la` commands before referencing in workflows.
- Document working directory context in comments.
- Never assume directory structure without verification.

**Example:**

```yaml
# Working directory: /repo/root
# Target: services/api/src
- name: Build API
  working-directory: services/api
  run: npm run build
```

**Validation Command:**

```bash
cd /repo/root && ls -la services/api/src
```

## 2.3 Conditional Branch Coverage

AI MUST:

- Create test events for ALL branches of conditional logic.
- Test each possible `if:` result (true/false paths).
- Provide event payloads for testing each branch.

**Example:**

```yaml
# Workflow with conditional
jobs:
  deploy:
    if: github.event_name == 'push' && github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    steps:
      - run: echo "Deploying to production"
```

**Test Cases Required:**

1. Event: push to main (condition: true)
2. Event: push to feature branch (condition: false)
3. Event: pull_request (condition: false)

## 2.4 Parameter Rename Protocol

AI MUST:

- Update all parameter definitions AND references across:
  - workflow files
  - composite actions
  - reusable workflows
  - documentation
- Validate completeness using grep to ensure no residual old names remain.

**Operational Steps:**

1. Identify all locations where parameter is defined or used
2. Perform find-and-replace across identified files
3. Execute grep validation: `grep -r "old_param_name" .github/ --include="*.yml" --include="*.yaml"`
4. Expected result: Zero matches (or only matches in comments explaining the rename)
5. If matches found: Update remaining references and repeat validation

**Example:**

Renaming `build-target` to `build_target`:

```bash
# Validation grep - must return zero results
grep -r "build-target" .github/ --include="*.yml" --include="*.yaml"
# Expected: (no output) or only comments referencing the old name
```

## 2.5 Version Pinning

AI MUST:

- Pin ALL GitHub actions to full commit SHAs (not tags or branches).
- Include inline comments documenting the semantic version.

**Example:**

```yaml
steps:
  - uses: actions/checkout@b4ffde65f46336ab88eb53be808477a3936bae11 # v4.1.1
  - uses: actions/setup-node@60edb5dd545a775178f52524783378180af0d1f8 # v4.0.2
```

## 2.6 Mandatory Linting & Validation

AI MUST enforce and validate against:

- `actionlint` for GitHub Actions workflows
- `yq` for YAML syntax validation
- `hadolint` for Dockerfiles
- Multi-stage Dockerfile build correctness

**Failure Handling:**

- If linting fails: AI MUST fix all issues before considering the task complete
- AI MUST report what was fixed and provide the linting output
- AI MUST re-run linting after fixes to confirm resolution

**Example Validation Commands:**

```bash
actionlint .github/workflows/*.yml
yq eval '.jobs' .github/workflows/build.yml
hadolint Dockerfile
docker build --target production .  # Validate multi-stage build
```

## 2.7 Naming Safety Protocol

AI MUST:

- Use only `[a-zA-Z0-9_]*` (alphanumeric + underscore) for identifiers used in GitHub expressions.
- Never introduce `-` (hyphen) in job names, step IDs, input names, or output names.
- Validate all identifier names against this regex pattern before using them.

**Rationale:** GitHub expressions treat hyphens as minus operators, causing parse errors.

**Example - CORRECT:**

```yaml
jobs:
  build_api:  # ✓ underscore is safe
    outputs:
      build_artifact: ${{ steps.build_step.outputs.result }}
```

**Example - INCORRECT:**

```yaml
jobs:
  build-api:  # ✗ hyphen causes expression errors
    outputs:
      build-artifact: ${{ steps.build-step.outputs.result }}  # ✗ will fail
```

**Exception:** File names and workflow names MAY use hyphens (e.g., `build-and-deploy.yml`)

---

# 3.0 WORKFLOW DEVELOPMENT STANDARDS

## 3.1 Structure Requirements

Workflows MUST:

- Use reusable components where possible.
- Define minimal permission scopes.
- Include explicit `working-directory` attributes.

## 3.2 Directory Context Documentation

AI SHALL insert comments documenting:

```
# From: <dir>
# To: <dir>
# Relationship: <path>
```

## 3.3 Command Behavior & Execution

AI MUST:

- Avoid long inline scripts when possible.
- Prefer composite actions for complex logic.

---

# 4.0 VALIDATION PROTOCOLS

## 4.1 Workflow Validation

AI MUST validate workflows against actionlint rules by:

- Checking syntax correctness (YAML structure, required fields)
- Validating event triggers match GitHub's event schema
- Ensuring inputs are properly defined and referenced
- Verifying outputs are correctly declared and accessible
- Checking shell commands for common errors (shellcheck rules)
- Validating action versions exist and are properly formatted

**Validation Approach:**

1. **Syntax Check:** Parse YAML structure for validity
2. **Schema Check:** Verify against GitHub Actions schema
3. **Reference Check:** Ensure all `${{ }}` expressions reference valid contexts
4. **Generate Command:** Provide `actionlint` command for user execution

**Example:**

```bash
# Generate this command for user to run
actionlint .github/workflows/build.yml
```

## 4.2 Dockerfile Validation

AI MUST ensure:

- Multi-stage build correctness (FROM stages are properly named and referenced)
- Proper ARG/ENV scoping (ARGs defined in correct stage, ENV persists correctly)
- Base image tags are pinned to specific versions (not `latest`)
- COPY operations reference valid stages and paths
- Build targets are testable independently

**Example Multi-Stage Validation:**

```dockerfile
# Stage 1: Builder (correctly scoped)
FROM node:20.11.0-alpine AS builder
ARG BUILD_ENV=production  # ARG only available in this stage
WORKDIR /app
COPY package*.json ./
RUN npm ci

# Stage 2: Production (correctly references builder)
FROM node:20.11.0-alpine AS production
ENV NODE_ENV=production  # ENV persists in runtime
COPY --from=builder /app/node_modules ./node_modules
COPY . .
CMD ["node", "server.js"]
```

**Validation Commands:**

```bash
hadolint Dockerfile
docker build --target builder -t app:builder .
docker build --target production -t app:production .
```

## 4.3 Terraform Validation

AI MUST:

- Format code recursively using `terraform fmt -recursive`
- Validate syntax using `terraform validate`
- Run tflint with project-specific configuration
- Identify required variable changes

**Validation Commands:**

```bash
# Format check (recursive)
terraform fmt -recursive -check

# Apply formatting
terraform fmt -recursive

# Validate syntax
terraform validate

# Run tflint with project config
tflint --config="$(git rev-parse --show-toplevel)/devops/terraform/.tflint.hcl" --recursive
```

---

# 5.0 AI EXECUTION PROTOCOL

## 5.1 AI Behavioral Requirements

AI MUST:

- Never hallucinate directory structures.
- Ask for missing information.
- Request confirmation before modifying workflows.

## 5.2 Deterministic Output

AI MUST:

- Produce consistent formatting (indentation, spacing)
- Use canonical YAML structure (proper anchors, references)
- Present changes clearly (show modified sections with context)
- Avoid including attribution comments in code unless explicitly requested

## 5.3 Commit Message Policy

AI MUST:

- Never include "Generated by AI", "Claude", or any AI attribution in commit messages
- Write clear, descriptive commit messages focused on the technical changes
- Follow the repository's existing commit message conventions

**Formatting Standards:**

- YAML: 2-space indentation
- Bash: 2-space or 4-space indentation (match existing)
- Terraform: Use `terraform fmt` standard
- Dockerfiles: Follow official best practices guide

## 5.4 Failure Mode Handling

If the AI detects ambiguity, it MUST:

1. Pause execution.
2. Request clarification.
3. Provide options.

---

# 6.0 NAMING CONVENTIONS (CRITICAL)

## 6.1 Identifier Rules

Identifiers used in GitHub expressions (job names, step IDs, input/output names) MUST:

- Match pattern: `[a-zA-Z][a-zA-Z0-9_]*` (start with letter, then alphanumeric + underscore)
- Never contain hyphens (-)
- Use snake_case for multi-word identifiers

## 6.2 File Naming Rules

Workflow and action files MAY:

- Use hyphens in filenames (e.g., `build-and-deploy.yml`)
- Use kebab-case for readability

## 6.3 Cross-Reference

See section 2.7 for detailed examples and rationale.

---

# 7.0 PATH & FILESYSTEM PROTOCOL

AI MUST:

- Document working directory before each path operation.
- Validate ALL relative paths.
- NEVER create a path assumption.

---

# 8.0 CONDITIONAL LOGIC PROTOCOL

AI MUST validate:

- Boolean conditions evaluate correctly
- Input presence checks prevent undefined access
- Fallback patterns using `|| ''` for optional inputs
- Complex expressions are properly parenthesized

**Example - Input Validation:**

```yaml
inputs:
  environment:
    required: false

jobs:
  deploy:
    # CORRECT: Handle optional input with fallback
    if: ${{ inputs.environment || '' != '' }}

    # CORRECT: Check for specific value
    if: ${{ inputs.environment == 'production' }}

    # INCORRECT: Direct boolean without fallback
    if: ${{ inputs.environment }}  # May cause errors if empty
```

**Example - Complex Conditions:**

```yaml
jobs:
  build:
    # CORRECT: Proper grouping
    if: ${{ (github.event_name == 'push' && github.ref == 'refs/heads/main') || github.event_name == 'workflow_dispatch' }}

    # INCORRECT: Ambiguous precedence
    if: ${{ github.event_name == 'push' && github.ref == 'refs/heads/main' || github.event_name == 'workflow_dispatch' }}
```

---

# 9.0 PARAMETER RENAME SPECIFICATION

AI MUST:

- Update `inputs:` definitions in all action.yml and workflow files
- Update all internal references within workflow steps
- Update all workflow_call and workflow_dispatch invocations
- Validate using grep to ensure complete rename

**Cross-Reference:** See section 2.4 for detailed operational steps and examples.

---

# 10.0 TESTING & VERIFICATION ENGINE

AI MUST produce:

- Complete `act` command sequences for local testing
- Event payload files (JSON) for conditional branch testing
- Documentation of expected outputs and success criteria
- Step-by-step verification instructions

**Example Test Package:**

```bash
# 1. Test push event to main branch
act -W .github/workflows/deploy.yml \
    --job deploy_production \
    --eventpath .github/test-events/push-main.json \
    --container-architecture linux/amd64

# 2. Test pull request event
act pull_request \
    --job run_tests \
    --eventpath .github/test-events/pr-event.json
```

**Example Event File (.github/test-events/push-main.json):**

```json
{
  "ref": "refs/heads/main",
  "repository": {
    "name": "test-repo",
    "owner": {"login": "test-user"}
  }
}
```

**Expected Output Documentation:**

- Exit code: 0 (success)
- Key log messages indicating successful execution
- Artifacts or outputs produced

---

# 11.0 DOCKERFILE QUALITY RULES

AI MUST:

- Use multi-stage builds for production images
- Pin base images to specific version tags (e.g., `node:20.11.0-alpine`, not `node:latest`)
- Validate ARG scope (ARG only available in the stage where defined)
- Use COPY instead of ADD (unless extracting tar archives)
- Minimize layer count by combining RUN commands where logical
- Use .dockerignore to exclude unnecessary files
- Run containers as non-root user when possible

**Recommended Base Images:**

- **Node.js:** `node:20-alpine` (specify minor version)
- **Python:** `python:3.12-slim` (slim variants for smaller size)
- **Go:** `golang:1.22-alpine` for builds, `alpine:3.19` for runtime
- **Java:** `eclipse-temurin:21-jre-alpine`

**Example Best Practice:**

```dockerfile
FROM node:20.11.0-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production

FROM node:20.11.0-alpine AS production
RUN addgroup -g 1001 -S nodejs && adduser -S nodejs -u 1001
WORKDIR /app
COPY --from=builder --chown=nodejs:nodejs /app/node_modules ./node_modules
COPY --chown=nodejs:nodejs . .
USER nodejs
EXPOSE 3000
CMD ["node", "server.js"]
```

---

# 12.0 TERRAFORM INFRASTRUCTURE RULES

AI MUST:

- Follow official Terraform best practices
- Enforce workspace standards
- Validate variable definitions
- Avoid unverified modules
- Run `terraform fmt -recursive` for formatting
- Execute `tflint` with project-specific configuration
- Validate with `terraform validate`

**Validation Workflow:**

```bash
# 1. Format code recursively
terraform fmt -recursive

# 2. Validate syntax
terraform validate

# 3. Run tflint with project config
tflint --config="$(git rev-parse --show-toplevel)/devops/terraform/.tflint.hcl" --recursive
```

**Cross-Reference:** See section 4.3 for detailed validation commands.

---

# 13.0 MULTI-LANGUAGE CODE STANDARDS

AI MUST enforce language-specific best practices:

## 13.1 Python

- Follow PEP8 style guide
- Use type hints for function signatures
- Use `black` or `ruff` for formatting
- Avoid mutable default arguments

## 13.2 Bash

- Pass shellcheck validation
- Quote all variable expansions: `"$VAR"`
- Use `set -euo pipefail` for safety
- Prefer `[[ ]]` over `[ ]` for conditionals

## 13.3 TypeScript

- Enable strict mode in tsconfig.json
- Avoid `any` type unless absolutely necessary
- Use interface for object shapes
- Prefer `const` over `let`

## 13.4 Go

- Follow `gofmt` standard formatting
- Use idiomatic error handling
- Prefer explicit error returns over panics
- Use meaningful variable names (no single letters except loops)

## 13.5 Java

- Follow standard naming conventions (CamelCase for classes)
- Use meaningful package names
- Implement proper exception handling
- Use try-with-resources for auto-closeable resources

---

# 14.0 CLOUD INFRASTRUCTURE RULES

AI MUST:

- Default to secure IAM policies
- Avoid public resources unless required
- Enforce tagging standards
- Validate network security settings

---

# 15.0 FAILURE MODE HANDLING

AI MUST detect and handle:

- Path errors
- Undefined variables
- Bad indentation
- Misaligned matrix configurations

---

# 16.0 AI BEHAVIORAL CONTRACTS

## 16.1 Idempotency

AI MUST:

- Produce predictable output
- Avoid regenerating unchanged sections

## 16.2 Transparency

AI MUST:

- Explain modifications when required
- Enumerate testing steps

## 16.3 Prohibition Rules

AI MUST NOT:

- Assume missing context
- Introduce dependencies without validation
- Produce partial changes

---

# 17.0 APPENDICES

## 17.1 Path Validation Macro

**Purpose:** Verify directory structure before referencing paths in workflows

**Template:**

```bash
cd <start_directory> && ls -la <target_path>
```

**Example:**

```bash
cd /workspace && ls -la services/api/src
```

**Expected Success:** Command returns 0 and shows directory contents

## 17.2 Grep Validation Macro

**Purpose:** Ensure complete parameter renames or find all references

**Template:**

```bash
grep -r "<search_string>" .github/ --include="*.yml" --include="*.yaml"
```

**Example:**

```bash
grep -r "old-param-name" .github/ --include="*.yml" --include="*.yaml"
```

**Expected Success for Rename:** Zero matches (or only explanatory comments)

## 17.3 Act Test Command

**Purpose:** Local workflow testing without pushing to GitHub

**Template:**

```bash
act -W .github/workflows/<workflow_file> \
    --job <job_name> \
    --eventpath <event_json_file> \
    --container-architecture linux/amd64
```

**Example:**

```bash
act -W .github/workflows/build.yml \
    --job build_production \
    --eventpath .github/test-events/push-main.json \
    --container-architecture linux/amd64
```

**Expected Success:** Exit code 0, workflow executes successfully

## 17.4 Common Validation Commands

**Actionlint:**

```bash
actionlint .github/workflows/*.yml
```

**Hadolint:**

```bash
hadolint Dockerfile
```

**Shellcheck:**

```bash
shellcheck scripts/*.sh
```

**Terraform Validation:**

```bash
terraform fmt -recursive -check
terraform validate
tflint --config="$(git rev-parse --show-toplevel)/devops/terraform/.tflint.hcl" --recursive
```

## 17.5 Cross-Reference Index

- **Naming Rules:** Sections 2.7, 6.0
- **Path Validation:** Sections 2.2, 7.0
- **Parameter Rename:** Sections 2.4, 9.0
- **Conditional Testing:** Sections 2.3, 8.0
- **Dockerfile Standards:** Sections 4.2, 11.0
- **Testing Requirements:** Sections 2.1, 10.0

---

**END OF SPECIFICATION**
