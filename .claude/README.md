# .claude/ — Contributor Config (Not Examples)

This directory is **Claude Code's config for working on promptcraft itself**. It is loaded automatically when a contributor opens this repo in Claude Code.

## Looking for Claude Code examples?

You are probably in the wrong place. Go to **[`tools/claude/`](../tools/claude/)** for:

- `examples/` — demonstration `.claude/` directories (hooks, agents, rules, skills, evals).
- `guides/` — how to set up and extend Claude Code.
- `templates/` — starter files to drop into your own repo's `.claude/`.
- `scaffolding/` — ready-to-copy project-rule directories.
- `specs/` — RFC-style standards.

## What's in here

- `CLAUDE.md` — project instructions loaded at session start. Mostly points to `../AGENTS.md`.
- `settings.json` — permissions and hook registration for this repo.
- `rules/` — contributor rules (PII discipline, git discipline, content quality).
- `hooks/` — safety hooks dogfooded from `../tools/claude/examples/hooks/`.
- `evals/` — regression cases for the dogfooded hooks.

## Why live here vs `tools/claude/examples/`?

- `tools/claude/examples/` is **curated reference material** — complete, polished, self-contained.
- `.claude/` is **live working config** — the hooks actually fire, the rules actually load. Breakage here is immediately visible.

When a pattern is proven out in `.claude/`, it gets distilled and published under `tools/claude/examples/`. When an example changes, we sync the live copy. See `CLAUDE.md` in this directory for the sync rule.
