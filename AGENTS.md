# AGENTS.md

Instructions for AI agents (Codex, Claude Code, Cursor, Copilot, Aider) working on *this* repo — **promptcraft**, a reference collection of prompts, rules, agents, and configs for AI coding assistants.

For content to *adopt* into your own projects, see `README.md` and the `shared/` / `tools/` directories. This file is about contributing to promptcraft itself.

## Project Overview

- **Purpose**: share production-tested patterns for working with Claude Code, Cursor, and ChatGPT.
- **Audience**: engineers setting up their own AI assistant configurations. Readers copy, adapt, and remix — they do not install promptcraft as a dependency.
- **Layout**:
  - `shared/` — tool-agnostic content (principles, language rules, infrastructure, workflows, quality standards).
  - `tools/<tool>/` — tool-specific adaptations (Claude Code, Cursor, ChatGPT).
  - `.claude/` — contributor config for working on this repo with Claude Code (not example content).
  - `.github/` — CI, issue/PR templates.
  - `docs/index.html` — social preview card. **Do not edit without a Pages plan.**
  - Root files: `README.md` (entry), `AGENTS.md` (this file), `ADOPTION.md`, `CONVENTIONS.md`, `DECISIONS.md`, `llms.txt`.

## Adding Content — Where Does It Go?

Ask in order:

1. **Does this apply to any AI assistant?** → `shared/`, under the relevant subdir (`principles/`, `languages/`, `infrastructure/`, `workflows/`, `quality/`).
2. **Is it specific to one tool?** → `tools/<tool>/`. Do not duplicate universal rules — link to `shared/`.
3. **Is it about contributing to this repo?** → `.claude/` (Claude Code contributor config), `CONVENTIONS.md`, or this file.

If a file in `tools/<tool>/` is restating a universal rule, it should be a pointer into `shared/` — not a copy.

## Editing Conventions

- **Markdown lint**: run `markdownlint -c .markdownlint.yaml '**/*.md'` before pushing. CI enforces.
- **Frontmatter for Claude skills/agents**: follow the YAML schema shown in `tools/claude/templates/` and in the [Claude Code skill docs](https://docs.claude.com/en/docs/claude-code/skills).
- **Cross-links**: all relative links must resolve. When moving a file, grep the repo for its old path and update every referrer.
- **One topic per file**: prefer consolidating related rules into one file per domain over creating a file per incident.
- **Concise by default**: rules loaded into every AI session cost tokens. Every line must justify itself.

## Commit & PR Guidelines

- **Conventional commits**: `type(scope): description` — `feat`, `fix`, `refactor`, `docs`, `chore`.
- **No AI attribution in commits or PR bodies** — no "Co-Authored-By: Claude" lines, no "Generated with…" footers. Content should read as authored by a human contributor.
- **One PR per logical change**. Refactors may bundle related moves; mixed-purpose PRs get split.
- **PR body**: summary + change list + breaking changes + test plan.
- **Run lint locally first**: `markdownlint` against all edited files. Don't rely on CI to catch formatting.

## Testing & Validation

- There are no code tests. Validation is:
  - Markdown lint passes (CI).
  - All relative links resolve.
  - `llms.txt` is in sync with the current file tree.
  - No broken code fences, YAML frontmatter, or table syntax.

## Nested AGENTS.md (Future)

Per the [agents.md](https://agents.md) convention, large subprojects may carry their own `AGENTS.md`. If `tools/claude/` or `tools/cursor/` grows editing conventions that diverge from this file, create `tools/<tool>/AGENTS.md`. Claude Code, Codex, and Cursor read the nearest one.

## Out of Scope

- `docs/index.html` — promotional asset; do not re-purpose without a Pages plan.
- `.claude/` hooks — these are maintenance config for the repo itself, not example content.
- Private/personal paths, company names, or PII in any file. See `CONVENTIONS.md`.
