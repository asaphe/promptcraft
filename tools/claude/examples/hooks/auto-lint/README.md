# Auto-Lint on Edit

PostToolUse hook that automatically runs the appropriate linter/formatter after every `Edit` or `Write` operation. Replaces advisory "please lint before committing" rules with deterministic enforcement.

## What it does

After Claude edits or creates a file, the hook detects the file type and runs the matching linter:

| File Type | Tool | Action |
|-----------|------|--------|
| `.py` | ruff | check --fix + format |
| `.tf` / `.tfvars` | terraform fmt | auto-format |
| `.ts` / `.tsx` / `.js` | prettier | auto-format |
| `.sh` | shellcheck | lint (report only) |
| `Dockerfile*` | hadolint | lint (report only) |
| `.yml` (workflows) | actionlint | lint (report only) |

## Design decisions

- **Extension-based checks run first** — shellcheck and hadolint check by extension regardless of path, so `.sh` files anywhere get linted (not just in a specific directory).
- **Path-based checks run second** — Language-specific tools (ruff, prettier) are scoped to the project's directory structure.
- **All tools degrade gracefully** — Missing tools are skipped via `command -v` checks or `|| true`. Only `jq` is required.
- **Stdout feedback** — Lint errors appear in Claude's context so it can self-correct.

## Customization

Edit the `case "$REL_PATH"` section to match your project structure. The example uses `python/`, `typescript/`, `infra/terraform/` — adjust to your monorepo layout.

## Layer

**Project** (`.claude/settings.json`) — Everyone on the team benefits from consistent formatting.
