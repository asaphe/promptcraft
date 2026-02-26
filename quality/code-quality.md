# Code Quality & Linting Standards

## Mandatory Quality Requirements

### 1. All Code Must Pass Linting

Every piece of code output must pass appropriate linters:

- **Shell Scripts**: Must pass `shellcheck` with no errors
- **Dockerfiles**: Must pass `hadolint` with no errors
- **Python**: Must pass `ruff` linting and formatting standards
- **Markdown**: Must pass markdown linting rules
- **YAML**: Must be valid and well-formed
- **TypeScript/JavaScript**: Must pass eslint standards
- **Terraform**: Must pass `terraform fmt` and `tflint`

### 2. Best Practices Adherence

Code should follow established best practices unless there's a compelling reason not to:

- Use official recommended patterns and idioms
- Follow security best practices (principle of least privilege, no hardcoded secrets, etc.)
- Apply performance and maintainability guidelines
- Use appropriate error handling and validation

### 3. Innovation Permission

Quality standards should not prevent innovative solutions:

- **Allowed**: New approaches, creative solutions, modern techniques
- **Encouraged**: Explaining why non-standard approaches were chosen
- **Required**: Ensuring innovative code still passes linting and security standards
- **Balance**: Innovation in logic/approach, standards in syntax/formatting

## Implementation Protocol

### 1. Iterative Improvement

Linting failures are opportunities to improve, not roadblocks:

- Present initial solution
- Run appropriate linters
- Fix any issues found
- Present final, lint-passing version

### 2. Explicit Linting Validation

When presenting code, show that it passes linting:

- Run relevant linters during development (or provide commands for user to execute)
- Fix issues before presenting final solution
- Document any linter exceptions and justifications
- If unable to run linters directly, explain validation steps and provide specific linting commands

### 3. Best Practice Documentation

When deviating from common patterns, explain why:

- State the standard approach
- Explain the specific reason for deviation
- Show how the alternative still meets quality standards

## Quality Without Innovation Limits

### DO

- ✅ Use cutting-edge tools and techniques that pass linting
- ✅ Propose creative solutions that follow syntax standards
- ✅ Challenge conventional approaches with well-linted alternatives

### DON'T

- ❌ Sacrifice code quality for speed
- ❌ Ignore linting errors "because it works"
- ❌ Use "it's innovative" as excuse for poor practices

## Security Standards

### Compliance Scanning

- Run daily secret scans for secret detection
- Implement container vulnerability scanning
- Apply security linting for infrastructure code
- Use security-focused base images and dependency scanning

### Access Control

- Never hardcode secrets in configuration files or containers
- Rotate secrets regularly and use automated secret injection
- Apply workload identity patterns for secure service communication
- Mask sensitive values in CI/CD logs and outputs

**Principle**: "Innovation in thinking, excellence in execution" - be creative with solutions but rigorous with implementation quality.
