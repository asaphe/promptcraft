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
├── mdc-rules/           # MDC (JSON) rules for project-level enforcement
│   ├── naming/                  # Naming convention rules
│   ├── formatting/              # Code formatting rules
│   ├── structure/               # Code structure rules
│   ├── documentation/            # Documentation requirements
│   ├── language-specific/        # Language-specific standards
│   ├── terraform/               # Terraform-specific rules
│   └── README.md                # MDC rules documentation
└── README.md            # This guide
```

## User Rules Setup (Recommended for Shared Repositories)

User Rules are perfect for shared repositories where you can't add project-level rules. They apply globally but don't interfere with existing Project Rules.

### Setup Steps

1. **Open Cursor Settings**: `Cmd/Ctrl + ,`
2. **Navigate to Rules**: Settings → Rules → User Rules
3. **Copy content** from desired `.md` files in `user-rules/`
4. **Paste into User Rules** text area
5. **Save settings**

### How User Rules Work with Project Rules

- **User Rules apply globally** across all your projects
- **Project Rules take precedence** when both exist (per Cursor's precedence order)
- **User Rules fill gaps** where Project Rules don't provide guidance
- **No conflicts**: User Rules are your personal preferences, Project Rules are project standards

**Example**: If a project has a Project Rule about using TypeScript, and your User Rule says "prefer Python", the Project Rule wins for that project. But in projects without TypeScript rules, your User Rule preference applies.

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

## User Rules vs Project Rules

According to [Cursor's official documentation](https://cursor.com/docs/context/rules), there are distinct rule types:

### User Rules (Global, Personal)

- **Location**: Cursor Settings → Rules → User Rules
- **Format**: Plain markdown text
- **Scope**: Global across all projects
- **Applied to**: Agent (Chat) only (not Inline Edit)
- **Use for**: Personal coding preferences, communication style, universal standards
- **Precedence**: Applied after Team Rules and Project Rules (lowest priority)

### Project Rules (Version-Controlled)

- **Location**: `.cursor/rules/` directory in your project
- **Format**: `.mdc` files (Markdown with frontmatter metadata)
- **Scope**: Project-specific, version-controlled
- **Applied to**: Agent (Chat) based on rule type and file patterns
- **Use for**: Domain-specific knowledge, project workflows, architecture decisions
- **Precedence**: Applied after Team Rules, before User Rules

### Rule Precedence Order

1. **Team Rules** (highest priority, if on Team/Enterprise plan)
2. **Project Rules** (`.cursor/rules/*.mdc` files)
3. **User Rules** (lowest priority, personal preferences)

**Key Insight**: User Rules complement Project Rules without conflicting. User Rules provide your personal preferences globally, while Project Rules provide project-specific standards. When both exist, Project Rules take precedence for project-specific guidance, while User Rules fill in gaps for personal preferences.

## Project Rules (`.mdc` Format)

Project Rules use `.mdc` format (Markdown with frontmatter) and are stored in `.cursor/rules/` directories. The `mdc-rules/` directory contains templates that can be converted to `.mdc` format for use in projects.

**Note**: The JSON files in `mdc-rules/` are templates/references. To use them as Cursor Project Rules, they should be converted to `.mdc` format. See `mdc-rules/README.md` for conversion guidance.

## Updating Rules

When the main rules are updated:

1. Regenerate Cursor-optimized versions
2. Copy new content to Cursor User Rules
3. Update MDC rules if patterns have changed
4. Restart Cursor to ensure rules are loaded

This setup provides maximum flexibility for both personal and professional development work!
