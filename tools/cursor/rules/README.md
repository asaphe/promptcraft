# tools/cursor/rules/

Cursor IDE rules in both supported formats.

## Contents

- `user/` — markdown files for Cursor's **user rules** UI (copy-paste into Settings → Rules). Always active across every project on your machine.
- `mdc/` — `.mdc` files for **project rules** (`.cursor/rules/*.mdc`). Frontmatter controls when each rule activates (globs, `alwaysApply`, `description`).

## Which to use?

- **`user/`** — personal preferences (communication style, code quality, general principles) that apply regardless of project.
- **`mdc/`** — project-scoped rules (language standards, infrastructure patterns, framework conventions). Commit these into the project's `.cursor/rules/` directory.

See Cursor's [Rules for AI](https://docs.cursor.com/context/rules) docs for details.
