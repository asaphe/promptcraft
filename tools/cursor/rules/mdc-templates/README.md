# Cursor `.mdc` Rule Templates (JSON → MDC)

JSON-encoded rule templates that need conversion to Cursor's official `.mdc` format before use. Each JSON file describes a rule's intent, file globs, and individual checks in structured form — useful as a starting point for writing a real `.mdc` rule.

> **These JSON files are NOT directly loadable by Cursor.** Cursor Project Rules use `.mdc` (Markdown with YAML frontmatter), not JSON. See [`../mdc/`](../mdc/) for ready-to-use `.mdc` files.

## Why both formats coexist

The JSON templates were authored as structured rule data — each rule carries `name`, `description`, `filePattern`, and a `rules[]` array of pattern/message/severity triples. Cursor's actual format is Markdown prose with frontmatter. The conversion is mechanical for simple rules, judgment-heavy for complex ones; the JSON is preserved here as raw material for that conversion.

## Layout

```text
mdc-templates/
├── naming/                    # Naming convention rules
│   ├── universal-naming.json
│   └── file-naming.json
├── formatting/                # Code formatting rules
│   └── code-formatting.json
├── structure/                 # Code structure / organization
│   └── terraform-structure.json
├── documentation/             # Documentation requirements
│   ├── markdown-docs.json
│   └── code-documentation.json
├── language-specific/         # Per-language standards
│   ├── typescript-javascript.json
│   ├── python.json
│   └── bash.json
├── terraform/                 # Terraform-specific rules
│   └── terraform-standards.json
└── README.md
```

## Converting a template to `.mdc`

### JSON template shape

```json
{
  "name": "Universal Naming Conventions",
  "description": "Enforces safe, portable identifier naming",
  "filePattern": "*.{ts,tsx,js,jsx,py}",
  "rules": [
    { "pattern": "^[a-z][a-zA-Z0-9_]*$", "message": "Use camelCase or snake_case", "severity": "error" }
  ]
}
```

### `.mdc` equivalent

```markdown
---
description: Universal naming conventions — safe, portable identifiers
globs:
  - "**/*.ts"
  - "**/*.tsx"
  - "**/*.js"
  - "**/*.jsx"
  - "**/*.py"
alwaysApply: false
---

# Universal Naming Conventions

Enforces safe, portable identifier naming across all languages.

## Rules

- Identifiers: alphanumeric + underscores only.
- Must start with a letter (not a number).
- Never use hyphens, dots, or spaces in identifiers.
- Valid: `deployment_name`, `userId`, `max_retry_count`.
- Invalid: `deployment-name`, `user.id`, `max retries`.
```

Save as `.cursor/rules/<rule-name>.mdc` in your project, then restart Cursor.

## Severity levels

JSON `severity` field maps to how strictly the rule should be enforced in prose:

- `error` → "Must be fixed" / use imperative verbs.
- `warning` → "Should be fixed" / use "prefer" or "avoid".
- `info` → "Suggestion" / phrase as guidance, not requirement.

## Suggested combinations

- **TypeScript/JS**: `naming/universal-naming`, `naming/file-naming`, `formatting/code-formatting`, `language-specific/typescript-javascript`, `documentation/code-documentation`.
- **Python**: same as TS but swap `language-specific/python`.
- **Terraform**: `terraform/terraform-standards`, `structure/terraform-structure`, `naming/universal-naming`.
- **Bash**: `language-specific/bash`, `naming/file-naming`.

## See also

- [`../mdc/`](../mdc/) — already-converted `.mdc` files (currently just `kubernetes-helm.mdc`).
- [`../user/`](../user/) — Markdown rules for Cursor's User Rules UI; not the Project Rules format.
- [Cursor Project Rules docs](https://cursor.com/docs/context/rules) — official spec.
