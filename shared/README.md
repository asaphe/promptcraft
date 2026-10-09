# shared/

Cross-tool source material for AI assistants (Claude Code, Cursor, ChatGPT, Codex, Copilot, Aider). Cross-tool does not mean mandatory in every project: select relevant principles and adapt language, backend, environment and workflow conventions to their actual contracts.

## What's here

- `principles/` — development principles, agent design, operational safety, tone & style, prompting examples.
- `languages/` — per-language coding standards (Python, TS/JS, Bash, Java/Go, general).
- `infrastructure/` — cloud & deployment patterns (AWS, Terraform, Kubernetes/Helm, Docker, Ansible).
- `workflows/` — CI/CD patterns, GitHub Actions.
- `quality/` — code quality, documentation, research standards.

## When to read

- Before writing tool-specific rules — `shared/` is the baseline, tool dirs layer on top.
- When a rule applies everywhere, edit it here. Tool-specific files should link to `shared/`, not duplicate it.

## Not here

- Tool-specific operational rules → `tools/<tool>/`.
- Contributor-only repo config → `.claude/`, `AGENTS.md`, `CONVENTIONS.md`.
