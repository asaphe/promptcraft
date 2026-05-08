# CLAUDE.md

`<TODO>` Replace this paragraph with one or two sentences describing your project: what it is, primary languages, services, infrastructure surface, and branch model. Keep it under 200 lines total in this file — see [`tools/claude/guides/CLAUDE.md`](../../guides/CLAUDE.md) for design guidance.

## On-Demand Reference (read when relevant)

- **Need to understand directory structure, modules, or databases?** Read `.claude/docs/architecture.md`.
- **Working on GitHub Actions, Terraform, Dockerfiles, or bash scripts?** Read `.claude/specs/ci-cd-spec.md`.
- `<TODO>` Add per-domain pointers as you accrue them (build commands, deploy runbooks, on-call playbooks).

## Specialized Agents

This scaffold ships two starter agents in `.claude/agents/` to demonstrate the pattern. Add more as your domain grows; see [`tools/claude/templates/agents/agent-template.md`](../../templates/agents/agent-template.md) for the shape and [`.claude/docs/agent-roster.md`](docs/agent-roster.md) for the cross-agent deferral table.

| Agent | When to Use |
|-------|-------------|
| **infra-expert**    | Infrastructure work (Terraform, k8s operators, ECR, networking) |
| **devops-reviewer** | Read-only PR review of Terraform, GitHub Actions, Dockerfiles, shell scripts |

## Code Standards

`<TODO>` Replace the bullets below with conventions actually enforced in your codebase. The defaults shown are illustrative — keep, edit, or remove per language reality.

- **Never use `Any` type** — always be explicit.
- **Use `| None` instead of `Optional`** in Python.
- API models use a typed schema layer (Pydantic, dataclasses, protobuf).
- Strict TypeScript; functional React components.
- Group imports: external/internal, alphabetized.
- Conventional commits: `feat:`, `fix:`, `refactor:`, `docs:`, `chore:`.
- Branch names follow `<ticket>-short-description` (`<TODO>` adapt to your ticket prefix).

## Operational Rules (`.claude/rules/`)

Auto-loaded rules from past operational experience live in `.claude/rules/` and are always in context.

When you encounter a correction, failure, or unexpected behavior during a session, proactively propose capturing it as a rule. Classify: agent-specific → agent definition, team-wide → `.claude/rules/`. Format each rule as a single bullet: `- **Rule title** — What to do and why.`

## Adapting this scaffold

- Replace every `<TODO>` marker.
- Add subdirectory `CLAUDE.md` files for any directory whose conventions diverge from the root (e.g., `frontend/CLAUDE.md`, `infrastructure/CLAUDE.md`). Claude Code loads the nearest one based on cwd.
- Add agents under `.claude/agents/` as new domains emerge — start from [`tools/claude/templates/agents/agent-template.md`](../../templates/agents/agent-template.md).
- Add skills under `.claude/skills/` for repeat workflows — see [`tools/claude/templates/skills/skill-template.md`](../../templates/skills/skill-template.md).
