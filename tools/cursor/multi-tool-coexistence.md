# Multi-Tool AI Coexistence Guide

How to configure a single codebase for multiple AI coding tools (Claude Code, Cursor, GitHub Copilot, Gemini CLI, etc.) without duplicating rules.

## The Problem

Each AI tool reads different configuration files:

| Tool | Primary Config | Also Reads |
|------|---------------|------------|
| **Claude Code** | `.claude/CLAUDE.md`, `.claude/rules/`, `.claude/agents/`, `.claude/skills/` | Subdirectory `CLAUDE.md` files |
| **Cursor** | `.cursor/rules/*.mdc` | `AGENTS.md`, `CLAUDE.md` (buggy, "third-party rules" toggle) |
| **GitHub Copilot** | `.github/copilot-instructions.md` | `AGENTS.md` |
| **Gemini CLI** | `GEMINI.md` | `AGENTS.md` |
| **Windsurf** | `.windsurfrules` | `AGENTS.md` |

Without coordination, teams end up maintaining the same standards in 3+ files.

## Solution: Pointer Architecture

Use `AGENTS.md` as a thin pointer to one authoritative source. Do not duplicate content.

```
AGENTS.md (pointer — all tools)
    ├── .cursor/rules/*.mdc (domain patterns — Cursor)
    └── .claude/ (orchestration, rules, agents — Claude Code)
```

### Why This Works

AI tools read `AGENTS.md` as markdown instructions, not as a parser. Writing "Read `.claude/CLAUDE.md` for project standards" is an instruction the AI model follows — it opens the file using its tools.

This is confirmed by [Cursor's official guidance](https://cursor.com/blog/agent-best-practices): "Reference files instead of copying their contents."

## AGENTS.md Template

```markdown
# AGENTS.md

[One-line project description.]

## Project Standards

Read `.claude/CLAUDE.md` for the full project context — it is the
authoritative source for code standards, DevOps standards, architecture,
and conventions.

For domain-specific code patterns, read the relevant file in
`.cursor/rules/` — each `.mdc` file targets a specific domain and
auto-loads based on file type globs.

## AI Tool Configuration

| System | Location | Purpose |
|--------|----------|---------|
| **Claude Code** | `.claude/` | Orchestration, operational rules, agents |
| **Cursor rules** | `.cursor/rules/*.mdc` | Domain code patterns, auto-loaded by file type |
```

## Design Principles

### 1. Single Source of Truth

Pick one system as authoritative. The other systems point to it. Good candidates:
- `.claude/CLAUDE.md` — if Claude Code is the primary tool (richest config system)
- `AGENTS.md` — if you want a tool-neutral single file

### 2. No Duplication

If a standard exists in `.claude/CLAUDE.md`, do not repeat it in `.cursor/rules/` or `AGENTS.md`. Instead, write a pointer: "For Terraform standards, see `.claude/specs/ci-cd-spec.md`."

### 3. Cursor Rules for Domain Patterns Only

Cursor's `.mdc` rules have glob-based auto-loading — they activate when you open matching files. Use this for domain-specific patterns (ClickHouse queries, workflow authoring, Helm charts) that benefit from contextual loading. General standards belong in the authoritative source.

### 4. Keep AGENTS.md Minimal

`AGENTS.md` should be under 30 lines. It exists to bridge tools, not to hold standards. The less content it has, the less maintenance it needs.

## Tool-Specific Notes

### Cursor

- Reads `AGENTS.md` natively (project root + subdirectories)
- Reads `CLAUDE.md` from project root as "third-party rules" — buggy, may load even when toggled off
- Cannot import/include files via MDC syntax — `@file` references are unreliable
- ~20K character limit per `.mdc` rule
- [Cursor rules docs](https://cursor.com/docs/context/rules)

### Claude Code

- Does **not** read `AGENTS.md` (as of March 2026) — [feature request #6235](https://github.com/anthropics/claude-code/issues/6235)
- Workaround: add `@AGENTS.md` reference in `CLAUDE.md`, or symlink
- Richest config system: agents, skills, hooks, rules with glob frontmatter, on-demand docs

### GitHub Copilot

- Reads `.github/copilot-instructions.md` and `AGENTS.md`
- No glob-based contextual loading

## Migration: Consolidating Existing Rules

If you already have rules in multiple systems:

1. **Audit for staleness** — Check `git log -1 --format="%ar" -- <file>` for each rule file
2. **Identify redundancy** — Diff overlapping rules (e.g., Terraform standards in `.cursor/` vs `.claude/`)
3. **Pick the authoritative version** — Usually the most recently maintained one
4. **Replace duplicates with pointers** — Keep glob triggers, replace body with "see X"
5. **Keep unique domain knowledge** — Rules with no equivalent in the other system stay as-is

## Anti-Patterns

- **Kitchen-sink cursor rules** — A single `.mdc` file aggregating all standards from other files. Hard to maintain, always stale.
- **Duplicating CLAUDE.md content in AGENTS.md** — Defeats the purpose. Any change requires updating both.
- **Ignoring the problem** — Standards diverge within weeks. Someone using Cursor gets different guidance than someone using Claude Code.
- **Symlink everything** — Symlinks break formatting differences (MDC frontmatter vs plain markdown).
