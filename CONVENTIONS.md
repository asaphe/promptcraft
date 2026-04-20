# CONVENTIONS.md

Structural and stylistic rules for content in this repo. If you're editing anything here, read this first.

## Repo layout

```text
/
├── shared/                  # Canonical universal content
│   ├── principles/          # Cross-assistant behavioral rules
│   ├── languages/           # Language-specific standards
│   ├── infrastructure/      # Cloud / infra patterns
│   ├── workflows/           # CI/CD, automation
│   └── quality/             # Code / docs / research quality
├── tools/<tool>/            # Tool-specific adaptations and extras
│   ├── claude/
│   ├── cursor/
│   └── chatgpt/
├── .claude/                 # Contributor config (editing THIS repo)
└── Root files               # README, AGENTS, ADOPTION, CONVENTIONS, DECISIONS, llms.txt
```

Each second-level directory has a `README.md` that lists contents and routing rules.

## Canonical-vs-copy rule

- **`shared/` is canonical.** If a rule applies across assistants, it lives in `shared/` once.
- **Tool directories reference, don't duplicate.** If `tools/cursor/rules/user/code-quality.md` restates `shared/quality/code-quality.md`, the Cursor file should eventually become a pointer. Duplication is a transitional state, not a goal.
- **Tool-specific files may layer on top** of a shared file — adapted phrasing, platform-specific caveats, or tool-UI wrappers (e.g., ChatGPT's 1500-char Custom Instructions).

## File naming

- Lowercase, hyphenated: `operational-safety-patterns.md`, not `OperationalSafetyPatterns.md`.
- Extension reflects format: `.md` for markdown, `.mdc` for Cursor project rules, `.sh` for shell, `.py` for Python, `.json` / `.jsonc` for data.
- Avoid version numbers or dates in filenames — use git history and frontmatter.
- Top-level root files use ALL-CAPS: `README.md`, `AGENTS.md`, `ADOPTION.md`, `CONVENTIONS.md`, `DECISIONS.md`, `LICENSE`. Everything else is lowercase.

## Markdown structure

- Start with an H1 that matches or summarizes the file's purpose.
- Follow immediately with a short purpose line (one sentence — "what is this file for").
- Use H2 for major sections. Avoid H4+; if you need that much nesting, consider splitting the file.
- Code fences always declare a language: ` ```bash `, ` ```python `, ` ```text `. Plain ` ``` ` is not acceptable.
- Tables for comparisons and routing; bullets for rule lists; prose for explanations.

## Frontmatter

- Cursor `.mdc` files MUST have YAML frontmatter with `description`, `globs`, and `alwaysApply` per Cursor's spec.
- Claude skill files (`SKILL.md`) MUST have frontmatter with `name`, `description`, `invoke_with`, `tools` per Claude Code's skill spec.
- Claude agent files MUST have frontmatter with `name`, `description`, `tools`, and optional `model` per Claude Code's agent spec.
- Plain markdown files under `shared/` and guides do NOT need frontmatter.

## Cross-links

- Always relative, never absolute URLs for intra-repo links.
- Verify resolution at authoring time — `ls path/to/target` from the file's directory.
- When you move a file, grep the repo for its old path and update every referrer:

```bash
grep -rn 'old/path' . --include='*.md'
```

- External links use full https URLs.

## Writing style

- Direct, terse, and load-bearing. Every line should earn its place — this content loads into limited-context AI sessions.
- Lead with the non-obvious insight. Don't build up to the point.
- Name specific commands, flags, error messages, file paths — not "use the right flag" or "check the docs".
- "Why" beats "what". If a rule isn't obvious, include a one-line rationale.
- No emojis unless the file is explicitly illustrative.

## Commits

- Conventional commits: `type(scope): description`.
  - Types: `feat`, `fix`, `refactor`, `docs`, `chore`.
  - Scope optional but encouraged: `feat(hooks)`, `docs(agents)`.
- Subject ≤72 chars, imperative mood.
- Body explains *why*, not *what* — the diff shows what.
- No AI attribution (`Co-Authored-By: Claude`, "Generated with...") in commits, PR bodies, or file content.

## PRs

- One logical change per PR. Refactors may bundle related file moves.
- PR body: summary → change list → breaking changes → test plan.
- Run `markdownlint -c .markdownlint.yaml '**/*.md'` locally before pushing.
- Check every relative link resolves (the stale-ref detection hook helps but isn't authoritative).

## Zero-PII

This is a public repo. Before every commit:

- No company names, personal names, or internal service names.
- No account IDs, workspace IDs, or region-specific internal URLs.
- No secrets, tokens, or token prefixes (`sk-`, `ghp_`, etc.).
- No internal Slack channels, Jira project keys, or CI tool URLs.

Grep your diff: `git diff --staged | grep -iE '(company|internal|token|account)'`.
