# Cursor `.mdc` Rule Templates (JSON → MDC)

JSON-encoded rule templates that need conversion to Cursor's official `.mdc` format before use. Each JSON file describes a rule's intent, file globs, and individual guidance entries in structured form — useful as a starting point for writing a real `.mdc` rule.

> **These JSON files are NOT directly loadable by Cursor.** Cursor Project Rules use `.mdc` (Markdown with YAML frontmatter), not JSON. See [`../mdc/`](../mdc/) for ready-to-use `.mdc` files.

## Why both formats coexist

The JSON templates were authored as structured rule data — each rule carries `name`, `description`, `filePattern`, and a `rules[]` array with messages, severity and optional illustrative patterns. Cursor's actual format is Markdown prose with frontmatter. The conversion is mechanical for simple rules, judgment-heavy for complex ones; the JSON is preserved here as raw material for that conversion.

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
  "name": "Source Identifier Conventions",
  "description": "Language-specific naming guidance; patterns are illustrative",
  "filePattern": "*.{ts,tsx,js,jsx,py}",
  "rules": [
    { "filePattern": "*.{ts,tsx,js,jsx}", "message": "Prefer camelCase variables and functions", "severity": "warning" },
    { "filePattern": "*.py", "message": "Prefer snake_case variables and functions", "severity": "warning" }
  ]
}
```

### `.mdc` equivalent

```markdown
---
description: Source identifier conventions for JavaScript, TypeScript and Python
globs:
  - "**/*.ts"
  - "**/*.tsx"
  - "**/*.js"
  - "**/*.jsx"
  - "**/*.py"
alwaysApply: false
---

# Source Identifier Conventions

Follow language and project conventions. Validate syntax and reserved names with the language parser or linter.

## Rules

- JavaScript/TypeScript: prefer camelCase variables and functions.
- Python: prefer snake_case variables and functions.
- Both: prefer PascalCase classes.
- Configuration keys and resource names follow their own schemas.
```

Save as `.cursor/rules/<rule-name>.mdc` in your project, then restart Cursor.

The legacy `naming/universal-naming.json` path now contains source-language guidance only. Its regexes illustrate text patterns; they do not enforce syntax or detect reserved words. YAML, JSON and Terraform are deliberately outside its file scope.

## Severity levels

JSON `severity` field maps to how strictly the rule should be enforced in prose:

- `error` → "Must be fixed" / use imperative verbs.
- `warning` → "Should be fixed" / use "prefer" or "avoid".
- `info` → "Suggestion" / phrase as guidance, not requirement.

## Suggested combinations

- **TypeScript/JS**: `naming/universal-naming`, `naming/file-naming`, `formatting/code-formatting`, `language-specific/typescript-javascript`, `documentation/code-documentation`.
- **Python**: same as TS but swap `language-specific/python`.
- **Terraform**: `terraform/terraform-standards`, `structure/terraform-structure`; use Terraform/provider schemas for configuration and resource names.
- **Bash**: `language-specific/bash`, `naming/file-naming`.

## See also

- [`../mdc/`](../mdc/) — already-converted `.mdc` files (currently just `kubernetes-helm.mdc`).
- [`../user/`](../user/) — Markdown rules for Cursor's User Rules UI; not the Project Rules format.
- [Cursor Project Rules docs](https://cursor.com/docs/context/rules) — official spec.
