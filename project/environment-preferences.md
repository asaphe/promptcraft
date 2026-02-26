# Environment & Project-Specific Preferences

> **Context**: These preferences apply to specific project environments and workflows. Only use these rules when explicitly indicated by the user or when working within the described project context. For general development work, refer to the universal rules in core/ and quality/ directories.

## Development Environment Configuration

### Python Environment

- The project uses pyenv with a virtual environment (name specific to project)
- Respect existing pyenv configuration and virtual environment setup
- Ensure commands work within the established virtual environment context

### Terminal and Shell Interaction

- Open terminal sessions that load custom dotfiles and settings rather than starting new vanilla shells
- Avoid unnecessary echo commands in terminal to display information
- Use existing shell configuration and aliases when available

## CLI Tool Behavior Standards

### Error Display and Output

- By default, CLI tools should display a summary of errors only
- Show detailed error messages when using the --verbose flag
- Use only the --max-rows CLI argument (default 30) to control table row display
- Specify --max-rows 0 to show all rows when needed

### Command Interface Design

- Implement consistent flag patterns across tools
- Provide both verbose and summary modes for output
- Use sensible defaults that work for most common use cases
- Allow fine-grained control when needed through specific flags

## Naming and Semantic Conventions

### Variable Naming Standards

- Prefer renaming variables with suffix '_resolved' instead of '_final' for semantic clarity
- Use descriptive names that clearly indicate the variable's purpose and state
- Apply consistent naming patterns across the entire codebase
- Consider semantic meaning when choosing between similar naming options

### Code Semantics

- Choose names that reflect the actual purpose and lifecycle of variables
- Use '_resolved' to indicate a variable that has been processed or calculated
- Avoid generic suffixes like '_final' when more specific terms are available
- Maintain consistency in naming patterns across different modules and services

## Project-Specific Technical Patterns

### Version Management

- Use single source of truth for package versions across CI/CD, Dockerfiles, and workflows
- Prefer dynamic version fetching from configuration files over hardcoded values
- Maintain consistency between lockfiles and deployment configurations
- Align version specifications across different parts of the system

### Integration Patterns

- Respect existing project architecture and established patterns
- Use project-specific conventions for naming and organization
- Follow established workflows and processes within the project
- Consider project-specific constraints and requirements in all solutions

## Cost and Resource Optimization

### Infrastructure Preferences

- Prefer using own compute resources over paid cloud services when possible
- Consider cost implications when suggesting third-party services
- Use efficient resource allocation patterns
- Optimize for both performance and cost-effectiveness

### Service Selection

- Evaluate cost-benefit ratio for external services
- Consider long-term operational costs in architecture decisions
- Prefer self-hosted solutions when security and cost requirements align
- Document cost considerations in architectural decision records
