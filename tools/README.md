# tools/

Tool-specific configurations, prompts, rules, and integrations. One subdirectory per AI assistant.

## What's here

- `claude/` — Claude Code configs (agents, rules, skills, hooks, scaffolding, and production examples).
- `cursor/` — Cursor IDE configs (user rules, `.mdc` scoped rules, MCP setup, conversation recovery utility).
- `chatgpt/` — ChatGPT custom instructions (global + per-project).

## When to read

- Picking up configs for a specific tool you use.
- Authoring new tool-specific content.

## Convention

- **Universal rules live in `shared/`**, not here. Tool dirs *layer* on top — they should not duplicate rules that apply to every tool.
- When adding tool-specific content, check `shared/` first; if the rule is universal, put it there and reference it from the tool dir.

## Not here

- Tool-agnostic principles, language rules, or infrastructure → `shared/`.
- Contributor-only repo config → `.claude/`, `AGENTS.md`.
