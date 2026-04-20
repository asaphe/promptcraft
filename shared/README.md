# shared/

Tool-agnostic content — applies to any AI assistant (Claude Code, Cursor, ChatGPT, Codex, Copilot, Aider).

## What's here

- `principles/` — development principles, agent design, operational safety, tone & style, prompting examples.
- `languages/` — per-language coding standards (Python, TS/JS, Bash, Java/Go, general).
- `infrastructure/` — cloud & deployment patterns (AWS, Terraform, Kubernetes/Helm, Docker, Ansible).
- `workflows/` — CI/CD patterns, GitHub Actions.
- `quality/` — code quality, documentation, research standards.

## When to read

- Before writing tool-specific rules — `shared/` is the baseline, tool dirs layer on top.
- When a rule applies everywhere, edit it here. Tool-specific files should link to `shared/`, not duplicate it.

## Audience

- Engineers adopting promptcraft patterns into their own AI assistant configs.
- Contributors editing universal rules.

## Not here

- Tool-specific operational rules → `tools/<tool>/`.
- Contributor-only repo config → `.claude/`, `AGENTS.md`, `CONVENTIONS.md`.
