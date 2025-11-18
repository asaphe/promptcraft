# MDC Rules Directory

This directory contains rule templates in JSON format that can be converted to Cursor Project Rules (`.mdc` format) for project-level enforcement.

## Important: Format Clarification

**These JSON files are NOT the correct format for Cursor Project Rules.**

According to [Cursor's official documentation](https://cursor.com/docs/context/rules), Project Rules use:

- **Format**: `.mdc` files (Markdown with frontmatter metadata)
- **Location**: `.cursor/rules/` directory in your project
- **Structure**: YAML frontmatter + Markdown content

The JSON files in this directory are:

- **Templates/References**: Structured data that can be converted to `.mdc` format
- **Source Material**: Based on standards from `user-rules/` directory
- **Conversion Needed**: Must be converted to `.mdc` format before use in Cursor

## Overview

These rule templates encode coding standards, naming conventions, and best practices that can be converted to Cursor Project Rules. They are based on the comprehensive standards defined in the `user-rules/` directory.

## Directory Structure

```text
mdc-rules/
├── naming/              # Naming convention rules
│   ├── universal-naming.json
│   └── file-naming.json
├── formatting/          # Code formatting rules
│   └── code-formatting.json
├── structure/          # Code structure and organization
│   └── terraform-structure.json
├── documentation/      # Documentation requirements
│   ├── markdown-docs.json
│   └── code-documentation.json
├── language-specific/   # Language-specific standards
│   ├── typescript-javascript.json
│   ├── python.json
│   └── bash.json
├── terraform/          # Terraform-specific rules
│   └── terraform-standards.json
└── README.md          # This file
```

## Converting to Cursor Project Rules

### Step 1: Convert JSON to `.mdc` Format

Cursor Project Rules use `.mdc` format with this structure:

```markdown
---
description: Rule description
globs:
  - "**/*.ts"
  - "**/*.tsx"
alwaysApply: false
---

# Rule Title

Rule content in markdown format...

## Naming Conventions

- Use camelCase for variables
- Use PascalCase for classes
```

### Step 2: Create `.mdc` Files

For each JSON rule file, create a corresponding `.mdc` file in your project's `.cursor/rules/` directory:

**Example Conversion:**

**JSON Template** (`naming/universal-naming.json`):

```json
{
  "name": "Universal Naming Conventions",
  "description": "Enforces safe, portable identifier naming",
  "filePattern": "*.{ts,tsx,js,jsx,py}",
  "rules": [...]
}
```

**Converted `.mdc` File** (`.cursor/rules/naming-conventions.mdc`):

```markdown
---
description: Universal naming conventions - safe, portable identifiers
globs:
  - "**/*.ts"
  - "**/*.tsx"
  - "**/*.js"
  - "**/*.jsx"
  - "**/*.py"
alwaysApply: false
---

# Universal Naming Conventions

Enforces safe, portable identifier naming across all languages and tools.

## Rules

- Identifiers must use only alphanumeric characters and underscores
- Must start with a letter (never a number)
- Never use hyphens, dots, or spaces in identifiers
- Valid examples: `deployment_name`, `userId`, `max_retry_count`
- Invalid examples: `deployment-name`, `user.id`, `max retries`
```

### Step 3: Use in Projects

1. Convert JSON templates to `.mdc` format
2. Place `.mdc` files in your project's `.cursor/rules/` directory
3. Configure rule type (Always Apply, Apply Intelligently, Apply to Specific Files, or Apply Manually)
4. Cursor will automatically apply these rules based on configuration

### Rule Selection

Choose rules based on your project:

**For TypeScript/JavaScript Projects:**

- `naming/universal-naming.json`
- `naming/file-naming.json`
- `formatting/code-formatting.json`
- `language-specific/typescript-javascript.json`
- `documentation/code-documentation.json`

**For Python Projects:**

- `naming/universal-naming.json`
- `naming/file-naming.json`
- `formatting/code-formatting.json`
- `language-specific/python.json`
- `documentation/code-documentation.json`

**For Terraform Projects:**

- `terraform/terraform-standards.json`
- `structure/terraform-structure.json`
- `naming/universal-naming.json`

**For Bash Scripts:**

- `language-specific/bash.json`
- `naming/file-naming.json`

## JSON Template Format

Each JSON template file follows this structure (for reference/conversion):

```json
{
  "name": "Rule Name",
  "description": "What this rule enforces",
  "version": "1.0.0",
  "author": "Promptcraft",
  "filePattern": "*.{ts,tsx}",
  "exclude": ["node_modules/**", "dist/**"],
  "rules": [
    {
      "pattern": "^[A-Z]",
      "message": "Error message",
      "severity": "error|warning|info"
    }
  ]
}
```

## Cursor Project Rule Format (`.mdc`)

The actual format for Cursor Project Rules is `.mdc` (Markdown with frontmatter):

```markdown
---
description: Rule description for Agent to understand when to apply
globs:
  - "**/*.ts"
  - "**/*.tsx"
alwaysApply: false
---

# Rule Title

Markdown content explaining the rule...

## Standards

- First standard
- Second standard
- Third standard

## Examples

Valid:
- `example1`
- `example2`

Invalid:
- `bad-example`
- `bad.example`
```

## Rule Severity Levels

- **error**: Must be fixed - code should not pass with these violations
- **warning**: Should be fixed - indicates potential issues or style violations
- **info**: Suggestions for improvement - optional enhancements

## Source Rules

These MDC rules are derived from the comprehensive standards in:

- `user-rules/core-principles.md` - Core development principles
- `user-rules/code-quality.md` - Code quality standards
- `user-rules/language-standards.md` - Language-specific patterns
- `user-rules/terraform-infrastructure.md` - Terraform standards
- `user-rules/general-principles.md` - Universal naming rules
- `user-rules/project-specific-standards.md` - Project conventions

## Customization

You can customize these rules for your specific project needs:

1. Copy the rule file to your project's `.cursor/rules/` directory
2. Modify patterns, severity levels, or file patterns as needed
3. Add project-specific rules following the same format

## Best Practices

1. **Start Small**: Begin with core naming and formatting rules
2. **Gradual Adoption**: Add more specific rules as your team adapts
3. **Review Regularly**: Update rules based on team feedback and evolving standards
4. **Document Exceptions**: Use `exclude` patterns for generated code or third-party files
5. **Version Control**: Track rule changes in version control

## Troubleshooting

### Rule Not Triggering

1. Check that file matches `filePattern` in rule
2. Verify file is not in `exclude` patterns
3. Ensure rule file is in `.cursor/rules/` directory
4. Restart Cursor after adding new rules

### Too Many Warnings

1. Adjust severity levels (error → warning → info)
2. Add more specific `exclude` patterns
3. Refine patterns to be more specific
4. Consider splitting rules into more focused files

### Performance Issues

1. Use specific `filePattern` to limit rule scope
2. Add comprehensive `exclude` patterns for build artifacts
3. Avoid overly complex regex patterns
4. Split large rule files into smaller, focused rules

## Related Resources

- [Cursor Official Rules Documentation](https://cursor.com/docs/context/rules) - Official guide to Project Rules, User Rules, and Team Rules
- User Rules: `../user-rules/` - Comprehensive markdown-based rules for Cursor User Rules
- Cursor Integration Guide: See `../README.md` for complete Cursor setup instructions

## Important Notes

1. **JSON files are templates only** - They must be converted to `.mdc` format for use in Cursor
2. **User Rules vs Project Rules** - User Rules (from `user-rules/`) are global preferences. Project Rules (`.mdc` files) are project-specific and version-controlled
3. **Rule Precedence** - Team Rules → Project Rules → User Rules (Project Rules take precedence over User Rules)
4. **No Conflicts** - User Rules complement Project Rules without interfering, as Project Rules take precedence for project-specific guidance

## Changelog

### 1.0.0 - Initial Release

- Created MDC rules from user-rules standards
- Organized by category (naming, formatting, structure, documentation, language-specific, terraform)
- Included universal naming conventions
- Added language-specific rules for TypeScript, Python, and Bash
- Added Terraform-specific rules
- Added documentation standards
