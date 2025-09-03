# Cursor Integration Guide

## Overview

This directory contains Cursor-optimized versions of our AI assistant rules, formatted for easy integration with Cursor IDE.

## Directory Structure

```text
cursor/
├── user-rules/           # Copy-paste into Cursor Settings → Rules
│   ├── core-principles.md        # Core development approach and protocols
│   ├── code-quality.md          # Quality standards and linting requirements
│   ├── language-standards.md    # Multi-language coding conventions
│   ├── terraform-infrastructure.md  # Terraform IaC, state management, modules
│   ├── infrastructure-tools.md  # Kubernetes, Docker, AWS, container orchestration
│   ├── workflow-patterns.md     # GitHub Actions, CI/CD, automation
│   ├── general-principles.md    # Universal standards and environment management
│   └── ansible-automation.md    # Ansible configuration management and automation
├── project-rules/        # MDC format for owned projects (.cursor/rules/)
│   └── (Future: MDC versions when needed)
└── README.md            # This guide
```

## User Rules Setup (Recommended for Shared Repositories)

Since you work on shared repositories where you can't add project-level rules:

1. **Open Cursor Settings**: `Cmd/Ctrl + ,`
2. **Navigate to Rules**: Settings → Rules → User Rules
3. **Copy content** from desired `.md` files in `user-rules/`
4. **Paste into User Rules** text area
5. **Save settings**

## Rule Selection

### Essential Core (Start Here)

- `core-principles.md` - Development approach, implementation strategy
- `code-quality.md` - Linting, testing, quality requirements
- `general-principles.md` - Universal standards, environment management

### Language-Specific

- `language-standards.md` - TypeScript, Python, Bash, Java, Go standards

### Infrastructure Focus

- `terraform-infrastructure.md` - Infrastructure as Code, state management, modules
- `infrastructure-tools.md` - Kubernetes, Docker, AWS, container orchestration
- `workflow-patterns.md` - GitHub Actions, CI/CD automation
- `ansible-automation.md` - Configuration management, idempotent design

## Best Practices

### File Size Management

- Each rule file is under 500 lines (Cursor recommendation)
- Focused, composable rules that can be combined as needed
- Split by logical domain for easier maintenance

### Content Style

- Comprehensive explanations with context (Unity-style approach)
- Structured sections: Context, Requirements, Examples
- Actionable instructions with reasoning
- Concrete examples and code snippets

### Usage Patterns

**For Personal Projects:**

- Copy multiple rule files as needed
- Combine related rules in single User Rules entry

**For Work Projects:**

- Use conservative core rules only
- Focus on code quality and development principles
- Avoid company-specific infrastructure rules

## Updating Rules

When the main rules are updated:

1. Regenerate Cursor-optimized versions
2. Copy new content to Cursor User Rules
3. Restart Cursor to ensure rules are loaded

This setup provides maximum flexibility for both personal and professional development work!
