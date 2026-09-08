# tools/claude/guides/

Design guides and reference docs for Claude Code.

## Index

| File | Purpose |
|------|---------|
| `claude-best-practices.md` | End-to-end best practices — context, planning, tools, workflow. |
| `CLAUDE.md` | How to structure a repo-level `CLAUDE.md` file. |
| `global-claude-md-guide.md` | How to design a personal `~/.claude/CLAUDE.md`. |
| `auto-memory-guide.md` | Designing effective persistent memory entries. |
| `hooks-guide.md` | Claude Code hooks — PreToolUse, PostToolUse, SessionStart, and common patterns. |
| `settings-json-guide.md` | `settings.json` permission allowlists, MCP, WebFetch, hooks. |
| `mcp-management-guide.md` | MCP server lifecycle — add, remove, team connectors, pitfalls. |
| `portability-guide.md` | Dotfiles, symlinks, backups, Desktop vs Code config. |
| `learning-system-guide.md` | Learning from corrections — detection signals, rule organization, retirement. |
| `multi-repo-kernel-sync.md` | Distributing shared rule kernels across repos via CI fan-out and local overlays. |
| `session-analytics-guide.md` | Analyzing `~/.claude/projects/*.jsonl` for token waste. |
| `pr-review-protocol.md` | Structured PR review routing and posting via `gh api`. |
| `stacked-prs-guide.md` | Native stacked pull requests — when to stack, per-layer approval cost, ruleset interactions, guard coverage. |
| `unattended-mode-guide.md` | Autonomous sessions with an absolute capability ceiling: the policy table, default-deny, and how to test it. |
| `github-actions-integration.md` | Using Claude Code in GitHub Actions workflows. |
| `issue-writing-guide.md` | Writing effective issues (proposals, bugs, design discussions). |
| `doc-quality-guide.md` | Documentation quality standards. |
| `pii-prevention-guide.md` | Preventing sensitive data leakage in public repos. |
| `public-contribution-guide.md` | End-to-end open-source contribution workflow. |

## When to read

- Before writing a new agent, skill, hook, or CLAUDE.md — read the relevant guide first.
- When stuck on a specific Claude Code feature (MCP, settings, memory) — look for the targeted guide.

## See also

- `../templates/` — ready-to-copy starter files (agents, skills, rules).
- `../examples/` — production implementations.
- `../../../shared/principles/agent-design-patterns.md` — tool-agnostic principles that underlie the Claude-specific design guide.
