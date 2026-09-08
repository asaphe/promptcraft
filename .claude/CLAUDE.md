# CLAUDE.md — Contributor Config

This file is Claude Code's project-level instructions **for working on promptcraft itself**. It is not example content. Readers looking for patterns to adopt should start at the repo root `README.md`.

General contribution rules live in `../AGENTS.md` (loaded by every AI assistant). This file adds only Claude-Code-specific guidance.

## Dogfooding Note

This repo runs its own example hooks from `../tools/claude/examples/hooks/`, copied into `.claude/hooks/`:

- `stateful-op-reminder.sh` — nudges (never blocks) on mutations to external systems.
- `destructive-guard.sh` — two-tier blocking (hard: push to main, destructive AWS; soft: PR ops, force-push).
- `pr-create-guard.sh` — blocks PR creation on missing prerequisites.

When updating a hook in `../tools/claude/examples/hooks/`, sync the `.claude/hooks/` copy too. Breaking dogfood = broken examples. CI enforces this: `.claude/scripts/check-mirrors.py` fails the build if a dogfooded copy has drifted from its published example.

Learning capture used to run here as three more hooks. It ships as the [claude-learning-loop](https://github.com/asaphe/claude-learning-loop) plugin now — install it yourself if you want it; this repo does not register it for you.

## Rules

Contributor-scoped rules live under `.claude/rules/`:

- `git-discipline.md` — branching, fetch-before-assert, no-stacking, PII scan.
- `content-quality.md` — accuracy discipline for a knowledge-base repo.
- `operational-discipline.md` — cross-platform and post-push hygiene.
- `pii-discipline.md` — zero-PII for a public repo.

Every change loads these into the Claude Code session automatically.
