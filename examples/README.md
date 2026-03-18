# Examples — Production Claude Code Configuration

Sanitized examples from a production monorepo (~40 services across Python, TypeScript, Go, and Java) with ~40 Terraform modules. These are real configurations that have been refined through daily use, with company-specific details replaced by placeholders.

## Directory Structure

### `agents/`

Specialist agent definitions — operational agents (deployment, Terraform, K8s troubleshooting) and review agents (DevOps, secrets, general code review). Each agent has a focused domain, clear boundaries, and explicit deferral rules.

### `config/`

Annotated `settings.json` excerpts showing two key patterns:

- **`settings-permissions.jsonc`** — Permission allowlists using Bash wildcards, MCP tool namespaces, WebFetch domain restrictions, and Skill permissions. Demonstrates the "wildcard + CLAUDE.md rules" approach to safety.
- **`settings-hooks.jsonc`** — Hook configuration for PreToolUse command rewriting (RTK token optimization) and statusline display.

### `docs/`

Supporting documentation referenced by agents and skills — PR review methodology, comment resolution procedures, review posting format, and agent roster.

### `hooks/`

- **`rtk/`** — PreToolUse hook that rewrites Bash commands through RTK (Rust Token Killer) for 60-90% token savings on CLI output. Includes the awareness rule that teaches Claude how to handle RTK failures.
- **`destructive-guard/`** — PreToolUse hook that blocks destructive git/GitHub operations (`gh pr close`, `git push --force`, `git reset --hard`, etc.). Forces Claude to ask the user before proceeding. Includes customization examples for Terraform, kubectl, and AWS.
- **`statusline/`** — Statusline command showing directory, git branch, AWS profile, model name, and context window usage with color-coded thresholds.

### `rules/`

Operational rules captured from production incidents and repeated corrections. Organized by domain:

- **`devops/`** — K8s deployment patterns (init container gotchas, pod idle verification)
- **`general/`** — Git safety, PR workflows, CI monitoring, execution discipline, operational safety, idempotent operations

### `skills/`

Slash-command skills that automate multi-step workflows:

- **`scan-history.md`** — Mines conversation history for patterns and candidate learnings
- **`pr-review.md`** — Routes PR files to specialist reviewer agents, collects findings, posts inline comments
- **`pr-resolver.md`** — Triages unresolved review comments, applies fixes, re-reviews, resolves threads
- **`open-ticket.md`** — Creates a project management ticket and git branch with smart defaults

## Disclaimer

These examples reflect one team's usage patterns and conventions. They are opinionated, shaped by a specific stack (EKS, Terraform, Helm, multi-tenant SaaS), and may not suit every project. Take them as-is for inspiration — not as prescriptive best practices. What works well in a 40-service monorepo with 14 agents may be overkill for a smaller codebase, and the specific rules encoded here come from real incidents and corrections that may not apply to your context.

## How to Use

1. **Browse for patterns** — These are reference implementations, not copy-paste templates. Read through to understand the patterns, then adapt for your project.
2. **Start with what you need** — You don't need all of this. A single `CLAUDE.md` with good rules is more valuable than a complex multi-agent setup used poorly.
3. **Customize the specifics** — Replace `<org>`, `<company>`, and other placeholders with your actual values. Adjust agent boundaries, review routing, and skill workflows to match your team's structure.

## Relationship to Other Directories

- **`claude/`** (guides) — Explains the *principles* behind each configuration area. These examples are *implementations* of those principles.
- **`claude/scaffolding/`** (starter templates) — Minimal starting points for new projects. These examples show where a mature project ends up after months of refinement. Start with scaffolding, evolve toward these patterns as your project grows.
