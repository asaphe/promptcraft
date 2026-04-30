# Skill Inventory

Skills shipped under `tools/claude/examples/skills/`. Invoke with `/{skill-name}` or via the Skill tool. The list below describes what each skill does at a high level — the authoritative description and `argument-hint` live in each skill's frontmatter and body.

## PR Lifecycle

| Slash Command | Skill | Purpose | When NOT to Use |
|---|---|---|---|
| `/pr-review [#PR]` | pr-review | Two-pass evidence-based PR review with domain routing | If your project doesn't have the referenced reviewer agents installed |
| `/pr-check [#PR]` | pr-check | CI status + comment triage | Fixing code and re-reviewing → use `/pr-resolver` |
| `/pr-resolver [#PR]` | pr-resolver | Fix review comments, commit, re-review, resolve threads | CI status / comment triage only → use `/pr-check` |
| `/pr-finalize [#PR]` | pr-finalize | Clean git history, update PR body, update tracker, verify docs | Fixing review comments → use `/pr-resolver` |

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

## Learning & Knowledge

| Slash Command | Skill | Purpose | When NOT to Use |
|---|---|---|---|
| `/scan-history` | scan-history | Mine session history (`~/.claude/projects/*.jsonl`) for candidate learnings, retry signals, long sessions | — |
| `/graduate-learnings` | graduate-learnings | Process pending learning candidates → classify → propose rule → write to target | Without the `learning-capture` hook family installed, this skill has no input |

## Related

- Agent routing: `.claude/docs/agent-roster.md`
- PR review routing (which reviewer for which files): `.claude/docs/pr-review-policy.md`
