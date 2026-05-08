# Designing a Project `CLAUDE.md`

How to structure a repo-level `CLAUDE.md` so Claude Code loads useful context on every session without bloating the context window.

## What it is

`CLAUDE.md` at a repo root is the project-level instruction file Claude Code reads automatically when a session starts in that directory. It is appended to the system prompt for every conversation. That makes it the single highest-leverage configuration surface — and the easiest place to leak token budget if you let it sprawl.

There are two distinct flavors:

- **Project `CLAUDE.md`** (lives at the repo root or in subdirectories). Scoped to that codebase. Concrete: file paths, build commands, deploy targets, named conventions.
- **Global `CLAUDE.md`** (lives at `~/.claude/CLAUDE.md`). Personal preferences applied across every project. See [`global-claude-md-guide.md`](global-claude-md-guide.md) for that flavor.

This guide is about the project flavor.

## What belongs in a project `CLAUDE.md`

Include facts the agent cannot derive from reading the code in 30 seconds:

- **Repo orientation.** What this project is, what stack, where the entry points are, which directories matter.
- **Build / test / deploy commands.** The exact commands to run locally and in CI. Agents waste turns guessing if these aren't named.
- **Conventions the codebase enforces.** Naming, structure, branch format, commit style — anything that has a "right answer" reviewers will flag.
- **Pointers, not content.** Reference rule files in `.claude/rules/`, runbooks in `.claude/docs/`, and templates in `.claude/templates/`. Don't inline what's already on disk.
- **Domain-specific guardrails.** "Never run X against prod", "always quote shell paths", "this codebase uses Y, not Z" — facts that prevent recurrent mistakes.

## What does NOT belong

- **Storytelling, history, rationale.** Belongs in PR bodies, ADRs, or a changelog — not loaded every session.
- **Content already in `.claude/rules/`.** Pointer once; let the rule file load itself when relevant.
- **Long lists of things the agent could grep for.** If a `find` would surface it in seconds, don't pre-load it.
- **PII, account IDs, secrets, internal service names.** A `CLAUDE.md` ends up in version control and (often) in screenshots — treat it as semi-public.
- **Stale dates, version numbers, "last reviewed" markers.** They rot fast and get loaded as fact every session.

## Length budget

- **Aim for under ~200 lines** of actual content. Above that, split into subdirectory `CLAUDE.md` files (Claude Code loads the nearest one based on cwd).
- **Every line loads on every session.** Multiply by your session count to see the token cost. A line that earns its place once a month is cheaper to look up than to pre-load.
- **If you find yourself scrolling past sections to find what you want, the agent will too.** That's the cue to split.

## Imperative voice, not narrative

Project `CLAUDE.md` is read by an agent that needs to act. Write rules and pointers, not paragraphs.

```text
Bad:  "Historically this project used npm but we migrated to pnpm
       in early 2025 because of the workspace handling. As of now,
       all package management goes through pnpm."

Good: "Use `pnpm` for all package operations. Never run `npm install`."
```

Imperative bullets are denser and easier for the agent to extract.

## Layered loading: subdirectory `CLAUDE.md`

Claude Code loads the nearest `CLAUDE.md` walking up from the cwd. Use this:

- Root `CLAUDE.md` — universal project facts.
- `frontend/CLAUDE.md` — TypeScript / React conventions, design system pointers.
- `infrastructure/CLAUDE.md` — Terraform module structure, workspace naming, apply discipline.
- `.github/CLAUDE.md` — workflow conventions, reusable action references.

Each is loaded only when the agent is working in that subtree, so frontend devs don't pay token cost for infrastructure rules and vice versa. This keeps the root file lean.

## Pointer pattern

Instead of inlining a rule body, reference the file:

```text
- Branch naming, commit format, PR body shape: see `.claude/rules/git.md`.
- Production safety checklist: `.claude/docs/production-safety.md`.
- Available specialist agents: `.claude/agents/` (see `.claude/docs/agent-roster.md` for the index).
```

Pointers cost ~one line; the agent only loads the target when it needs to.

## Common mistakes

- **Pasting in `claude init` output and never editing it.** The default contains placeholder language ("This directory contains comprehensive guidance for...") that's misleading without project-specific facts. Replace it.
- **Listing files instead of describing structure.** Agents can `ls`. They can't infer "this is the build entry point."
- **Mixing global preferences with project facts.** Personal preferences (review style, communication tone) belong in `~/.claude/CLAUDE.md`, not in every project file.
- **Referencing files that don't exist.** A pointer to `.claude/docs/build-commands.md` is broken if that file isn't shipped. Audit cross-references when you edit.
- **Leaking internal context.** Tech-stack version numbers, account IDs, internal service names — all end up in `git log` and screenshots. Keep the file public-safe.

## Maintenance signals

Update the `CLAUDE.md` when:

- A new convention takes hold that the agent should follow.
- A previously-stable command changes (`pytest` → `pytest -p test`, `deploy` → `deploy --env`).
- A rule file is added/renamed/removed (update pointers).
- A common mistake recurs that would have been prevented by an explicit rule.

Don't update it just because time passed. Stale rules are worse than absent ones.

## Examples in this repo

- [`../scaffolding/.claude/CLAUDE.md`](../scaffolding/.claude/CLAUDE.md) — a starter project `CLAUDE.md` you can copy and edit.
- [`../examples/config/global-CLAUDE.md`](../examples/config/global-CLAUDE.md) — the *global* flavor for comparison; note the different tone and scope.

## See also

- [`global-claude-md-guide.md`](global-claude-md-guide.md) — designing the personal `~/.claude/CLAUDE.md`.
- [`auto-memory-guide.md`](auto-memory-guide.md) — when to use persistent memory vs. inline `CLAUDE.md` content.
- [`../../../shared/principles/modular-composition.md`](../../../shared/principles/modular-composition.md) — single-purpose modular rule files instead of one mega-CLAUDE.md.
