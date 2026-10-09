# tools/claude/

Claude Code configurations, guides, templates, and production examples.

## What's here

- `guides/` — design guides for Claude Code agents, skills, hooks, CLAUDE.md, MCP, portability, PR review, and more. Start here to understand *how* Claude Code is meant to be configured.
- `templates/` — ready-to-copy starter files: agents, skills, rules, project docs.
- `scaffolding/` — a complete example `.claude/` directory. Copy and customize for a new repo.
- `specs/` — RFC-style specifications (e.g., CI/CD standards).
- `examples/` — sanitized production configs from real projects (agents, hooks, skills, rules).

## When to read

For first adoption, use the [standalone baseline](examples/config/global-CLAUDE.md) and the four guarded recipes in [ADOPTION.md](../../ADOPTION.md). The [operations profile](examples/profiles/README.md), hooks and infrastructure scaffold are separate opt-in additions. The [advanced global profile](examples/config/global-CLAUDE-advanced.md) and specialized rules are reference-only; do not bulk activate examples.

- Setting up Claude Code in a new repo → `scaffolding/` + `guides/`.
- Adding a new agent/skill/hook → `templates/` + `guides/`.
- Looking for a proven pattern → `examples/`.

## Not here

- Claude Code contributor config for *this* repo → `.claude/` at repo root.
- Tool-agnostic principles (agent design, operational safety, tone) → `shared/principles/`.
