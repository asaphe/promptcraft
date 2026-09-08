# Skill Inventory

Skills shipped under `tools/claude/examples/skills/`. Invoke with `/{skill-name}` or via the Skill tool. The list below describes what each skill does at a high level — the authoritative description and `argument-hint` live in each skill's frontmatter and body.

## PR Lifecycle

| Slash Command | Skill | Purpose | When NOT to Use |
|---|---|---|---|
| `/pr-check [#PR]` | pr-check | CI status + comment triage | Fixing code and re-reviewing → use `/pr-resolver` |
| `/pr-resolver [#PR]` | pr-resolver | Fix review comments, commit, re-review, resolve threads | CI status / comment triage only → use `/pr-check` |

Review and finalize moved to [claude-reviewkit](https://github.com/asaphe/claude-reviewkit) as `/reviewkit:review` and `/reviewkit:finalize`.

## Ticket & Branch

| Slash Command | Skill | Purpose | Notes |
|---|---|---|---|
| `/open-ticket [title]` | open-ticket | Create task ticket + git branch | Generic — adapt the tracker integration to your stack |

## DevOps

| Slash Command | Skill | Purpose | Notes |
|---|---|---|---|
| `/eks-check [namespace] [pod]` | eks-check | Standard EKS diagnostic sequence for failing/pending/crashlooping pods | Assumes ESO + Karpenter — adapt branches to your stack |
| `/check-secret [app] [deployment]` | check-secret | Drift detection across AWS Secrets Manager → ExternalSecret → K8s Secret → pod env | Read-only |
| `/new-gh-action [name]` | new-gh-action | Scaffold a GitHub Actions composite action or workflow | Runs `actionlint` after scaffolding |

## Frontend

| Slash Command | Skill | Purpose |
|---|---|---|
| `/sentry-react` | sentry-react | Load Sentry instrumentation patterns for React webapps (errors, tracing, structured logs) |

## Evaluation & Tooling

| Slash Command | Skill | Purpose |
|---|---|---|
| `/eval-tool [tool-name-or-url]` | eval-tool | Security evaluation framework for adopting a new dev tool / extension / MCP server / dependency |

## Session State

| Slash Command | Skill | Purpose | When NOT to Use |
|---|---|---|---|
| `/recap [handoff-file]` | recap | Render the work in front of you as goal / where-we-are / done / open / next, then end the turn | Asking what a *different* session did → use `/sessions` |
| `/sessions [list\|show\|grep]` | sessions | Query the session-log corpus for what past or other sessions did and where they stopped | Looking for the *wording* of a past prompt → use `/history-search` |

`/sessions` requires the [session-log](../hooks/session-log/) Stop hook, which writes the corpus it reads. `/recap` works without it and falls back to `/sessions` only when the current thread has no state to render.

## Learning & Knowledge

Session mining and learning codification moved to [claude-learning-loop](https://github.com/asaphe/claude-learning-loop) as `/learning-loop:learn-scan`, `/learning-loop:wrap-up`, `/learning-loop:eval` and `/learning-loop:learn`.

## Related

- Agent routing: `.claude/docs/agent-roster.md`
- PR review routing (which reviewer for which files): `.claude/docs/pr-review-policy.md`
