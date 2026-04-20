# Skill Inventory

All 30 skills available in this repo, organized by category. Invoke with `/{skill-name}` or via the Skill tool.

## SDLC Pipeline (Feature Lifecycle)

| Slash Command | Skill | Purpose | When NOT to Use |
|---|---|---|---|
| `/sdlc` | sdlc | Pipeline guide, domain info, next-action suggestion | Use specific phase skills directly when you know what phase you're in |
| `/sdlc-define` | sdlc-define | Research + task story creation | — |
| `/sdlc-design` | sdlc-design | High-level architecture plan | — |
| `/sdlc-triage` | sdlc-triage | Break feature into subtasks | — |
| `/sdlc-plan` | sdlc-plan | Detailed engineering plan | Ad-hoc planning without task context |
| `/sdlc-implement` | sdlc-implement | Agentic coding with tiered self-review | — |
| `/sdlc-review` | sdlc-review | PR review with SDLC + task context | Quick standalone reviews → use `/pr-review` |
| `/sdlc-handover` | sdlc-handover | Feature summary + ADR consolidation | — |
| `/sdlc-sprint` | sdlc-sprint | Sprint lifecycle (status, candidates, retro) | Real-time at-risk snapshots → use `/sprint-report` |
| `/sdlc-tasks` | sdlc-tasks | Cross-sprint dependency-aware task query | Personal task view → `/my-tasks`; sprint board → `/sprint-tasks` |

## PR Management

| Slash Command | Skill | Purpose | When NOT to Use |
|---|---|---|---|
| `/pr-check [#PR]` | pr-check | CI status + comment triage | Fixing code and re-reviewing → use `/pr-resolver` |
| `/pr-resolver [#PR]` | pr-resolver | Fix review comments, commit, re-review, resolve threads | CI status / comment triage only → use `/pr-check` |
| `/pr-review [#PR]` | pr-review | Standalone PR review with domain routing | SDLC-tracked PRs needing task context → use `/sdlc-review` |

## Sprint & Task View

| Slash Command | Skill | Purpose | When NOT to Use |
|---|---|---|---|
| `/my-tasks [status]` | my-tasks | Personal tasks across all lists | Sprint board → `/sprint-tasks`; dependency-aware → `/sdlc-tasks` |
| `/sprint-tasks [assignee]` | sprint-tasks | Current sprint board | Personal cross-workspace view → `/my-tasks` |
| `/sprint-report [team]` | sprint-report | Real-time sprint snapshot with at-risk flags | End-of-sprint retrospective → `/sdlc-sprint summary` |
| `/task PROJ-XXXX` | task | Single task detail view | Multiple tasks → `/sdlc-tasks` or `/sprint-tasks` |

## Ticket & Branch

| Slash Command | Skill | Purpose | When NOT to Use |
|---|---|---|---|
| `/open-ticket [title]` | open-ticket | Create task ticket + git branch | Never proactively — only on explicit request |

## DevOps Operations

| Slash Command | Skill | Purpose | Notes |
|---|---|---|---|
| `/deploy` | devops/deploy | Trigger deployment workflow | Requires image tag resolution; confirms before triggering |
| `/verify-deploy` | devops/verify-deploy | Post-deploy health check | GREEN/YELLOW/RED summary |
| `/tf-plan` | devops/tf-plan | Terraform plan with pre-flight checks | Workspace validation included |
| `/check-secret [name]` | devops/check-secret | Inspect secret across SM + ExternalSecret + pod env | Drift detection |
| `/new-gh-action` | devops/new-gh-action | Scaffold GitHub Action or workflow | Runs actionlint after scaffolding |
| `/new-tf-module` | devops/new-tf-module | Scaffold Terraform module | Follows module conventions from devops/terraform/CLAUDE.md |

> **Note:** The `Skill` column shows the folder path under `.claude/skills/` for human navigation. The slash command (first column) is the authoritative invocation key — use `/deploy`, not `skill: "devops/deploy"`.

## Scaffolding — Mesh

| Slash Command | Skill | Purpose | When NOT to Use |
|---|---|---|---|
| `/new-mesh-feature` | mesh/new-mesh-feature | Scaffold mesh feature with step contracts | Workflow-only agents (no step contracts) → `/new-mesh-workflow` |
| `/new-mesh-workflow` | mesh/new-mesh-workflow | Scaffold workflow-only mesh agent | When step contracts are also needed → `/new-mesh-feature` |
| `/release-<service>` | mesh/release-service | Create service release with release notes | — |

## Scaffolding — IO Team

| Slash Command | Skill | Purpose |
|---|---|---|
| `/new-io-team-lambda` | io/new-io-team-lambda | Scaffold Lambda function for IO team |

## Learning & Knowledge

| Slash Command | Skill | Purpose | When NOT to Use |
|---|---|---|---|
| `/knowledge-loop` | knowledge-loop | Capture new patterns/anti-patterns into cursor rules | Personal preferences → auto memory |
| `/scan-history` | scan-history | Mine session history for candidate learnings | — |

## Related

- Agent routing: `.claude/docs/agent-roster.md`
- PR review routing (which reviewer for which files): `.claude/docs/pr-review-policy.md`
- SDLC domains: `.claude/sdlc/domains/`
