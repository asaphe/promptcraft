# Cursor Project Rules (`.mdc`)

This directory contains ready-to-use Cursor Project Rules in the official `.mdc` format. Copy any file here directly into your project's `.cursor/rules/` directory — Cursor will load it on next session.

## Format

Each `.mdc` file is Markdown with YAML frontmatter:

```markdown
---
description: One-line summary of what this rule enforces
globs:
  - "**/*.tf"
alwaysApply: false
---

# Rule body in Markdown...
```

See [Cursor's Project Rules docs](https://cursor.com/docs/context/rules) for the full spec.

## Contents

| File | Scope | Globs |
|------|-------|-------|
| `kubernetes/kubernetes-helm.mdc` | Kubernetes + Helm operational rules | `**/*.yaml`, `**/Chart.yaml`, `**/values*.yaml`, `**/*.tf` |

## Adoption

```bash
mkdir -p /path/to/your-project/.cursor/rules/
cp tools/cursor/rules/mdc/<topic>/<rule>.mdc /path/to/your-project/.cursor/rules/
```

Then restart Cursor or reload the project.

## See also

- [`../mdc-templates/`](../mdc-templates/) — JSON rule templates that need conversion to `.mdc` before use. The templates encode rule logic in a structured form that hasn't yet been written up as a Markdown rule.
- [`../user/`](../user/) — Markdown rules for Cursor's User Rules UI (Settings → Rules), not the Project Rules format.
