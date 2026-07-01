# Agent Team Protocols

Coordination protocols for multi-agent teams. Teams compose existing agents (`.claude/agents/*.md`) — they don't replace them. Solo agent spawning remains the default for single-domain tasks.

> Teams spawn full peer agent instances and are token-expensive. Treat them as opt-in for work that genuinely needs agents to message *each other*; for everything else, subagent fan-out or a decision-panel skill is cheaper. See the policy gate at the end.

## When to Use Teams vs Independent Agents

| Scenario | Use |
| --- | --- |
| Single-domain task (e.g., only Terraform files) | Solo agent |
| Mixed-domain PR review | PR Review Team |
| Multi-symptom production failure | Incident Response Team |
| Full feature lifecycle (implement → review → merge) | SDLC Feature Team |
| Deploy + monitor + troubleshoot | Deployment Orchestration Team |

## PR Review Team

**Purpose:** Coordinated review of mixed-domain PRs with file-scope assignment, parallel review, and finding deduplication.

### PR Review Team — roles

| Role | Agent Type | Responsibility |
| --- | --- | --- |
| **review-lead** | (main context) | Reads diff, classifies files, assigns scope, deduplicates findings, posts review |
| **devops-reviewer** | `devops-reviewer` | Reviews Terraform, GHA, Dockerfiles, shell scripts |
| **general-reviewer** | `general-reviewer` | Reviews Python, TypeScript, Go, Java app code |
| **secrets-reviewer** | `secrets-reviewer` | Reviews secret tfvars, ExternalSecret configs |
| **db-reviewer** | `clickhouse-reviewer` (or your DB reviewer) | Reviews SQL, schema, migrations |
| **agent-config-reviewer** | `agent-config-reviewer` | Reviews `.claude/` configuration |

### PR Review Team — protocol

1. **Lead reads PR diff** — `gh pr diff --name-only` to get file list
2. **Lead classifies files** — Maps each file to a reviewer domain using the routing table in `pr-review-policy.md`
3. **Lead creates team** — Only spawns reviewers for domains with files to review
4. **Lead creates scoped tasks** — One task per reviewer: "Review these files: {file_list}"
5. **Reviewers work in parallel** — Each reads only their assigned files, produces findings
6. **Reviewers message lead** — Send findings as structured markdown when done
7. **Lead deduplicates** — Same file+line from multiple reviewers → merge severity upward (SUGGESTION < ISSUE < BLOCKING)
8. **Lead presents consolidated findings** — Single table to user for approval
9. **Lead posts review** — Per `pr-review-posting.md`
10. **Lead shuts down team**

## Incident Response Team

**Purpose:** Parallel investigation of production failures with shared context and "found it" broadcasting.

### Incident Response Team — roles

| Role | Agent Type | Responsibility |
| --- | --- | --- |
| **triage-lead** | (main context) | Reads symptoms, selects investigators, compiles summary |
| Investigators (2-3) | Selected from: `pipeline-expert`, `k8s-troubleshooter`, `secrets-expert`, `deployment-expert`, `data-platform-expert` | Probe assigned dimension in parallel |

### Symptom → Team Mapping

| Primary Symptom | Investigators |
| --- | --- |
| CI/CD failure (workflow red, build broken) | `pipeline-expert` + `deployment-expert` |
| Pod crash / OOM / scheduling failure | `k8s-troubleshooter` + `deployment-expert` |
| Secret sync error / missing env var | `secrets-expert` + `k8s-troubleshooter` |
| Data pipeline failure (orchestrator / transformation job) | `data-platform-expert` + `k8s-troubleshooter` |
| Deployment rollout failure | `deployment-expert` + `k8s-troubleshooter` + `secrets-expert` |
| Multiple / unclear symptoms | `k8s-troubleshooter` + `deployment-expert` + `secrets-expert` |

### Incident Response Team — protocol

1. **Lead reads initial signal** — CI log, alert, user report
2. **Lead classifies symptoms** — Maps to investigator set above
3. **Lead creates team** — Spawns 2-3 investigators with shared context (environment, deployment, timeline)
4. **Investigators probe in parallel** — Each assigned a specific dimension (pods, secrets, pipelines, etc.)
5. **First to find root cause messages lead** — "Found it: {root cause}. Recommended fix: {action}"
6. **Lead broadcasts to team** — Other investigators stop probing, shift to verification
7. **Lead compiles incident summary** — Root cause, timeline, fix, prevention

## SDLC Feature Team

**Purpose:** Persistent context across implementation phases — no re-reading between implement, self-review, and PR creation.

### SDLC Feature Team — roles

| Role | Agent Type | Responsibility |
| --- | --- | --- |
| **sdlc-lead** | (main context) | Manages phase transitions, tracks progress |
| **implementer** | `general-purpose` | Writes code following engineering plan |
| **self-reviewer** | domain-appropriate reviewer | Reviews after each step |

### SDLC Feature Team — protocol

1. **Lead loads context once** — issue-tracker task, branch, engineering plan, domain references
2. **Lead shares context with team** — Via initial message to implementer
3. **Implementer codes step-by-step** — Messages self-reviewer after each step
4. **Self-reviewer provides feedback** — Implementer fixes inline
5. **After all steps** — Lead triggers PR creation, optionally spawns full review team (PR Review Team pattern)
6. **Lead posts implementation note** to the issue tracker

## Deployment Orchestration Team

**Purpose:** Overlapping deployment phases — monitoring starts during apply, troubleshooter has full context on failure.

### Deployment Orchestration Team — roles

| Role | Agent Type | Responsibility |
| --- | --- | --- |
| **deploy-lead** | (main context) | Coordinates phases, reports status |
| **tf-expert** | `terraform-expert` | Runs plan/apply |
| **deploy-monitor** | `deployment-expert` | Monitors rollout health |
| **k8s-standby** | `k8s-troubleshooter` | Activates on pod failure (standby until needed) |

### Deployment Orchestration Team — protocol

1. **TF expert runs plan** — Messages lead with result
2. **Lead presents plan to user** — Waits for approval
3. **On approval, TF expert applies** — Messages lead when apply starts
4. **Deploy monitor starts immediately** — Watches pod rollout in parallel with apply completion
5. **If pods fail** — Deploy monitor messages k8s-standby with failure details + full deployment context
6. **K8s-standby investigates** — Already has deployment context, no re-reading needed
7. **Lead reports final status**

## Team Lifecycle

All teams follow this lifecycle:

1. **Create** — Create the team with a descriptive name
2. **Spawn members** — Spawn agents with the team name and a member name, using the appropriate agent type
3. **Assign work** — Tasks via the task tools, or direct messages between members
4. **Coordinate** — Members communicate via messages, lead monitors progress
5. **Collect results** — Members send findings/status to lead
6. **Shutdown** — Lead sends a shutdown request to each member, then deletes the team

## Design Principles

- **Agents stay as-is** — `.claude/agents/*.md` files define domain expertise. Teams compose agents, not replace them.
- **Deferral rules stay** — Agents still know their boundaries. Teams just make handoffs faster.
- **Solo spawning is default** — Teams are opt-in for multi-domain work.
- **Read-only agents stay read-only** — No file conflict risk in review teams.
- **Team members need full context** — Subagents don't inherit parent context. Include all necessary instructions and file references in the spawn prompt.

## Teams are a deliberate escalation (policy gate)

Agent teams spawn full peer agent instances and can cost several times the tokens of a single session (especially when teammates run a planning model). Keep them disabled by default and reach for subagent fan-out or a decision-panel skill instead.

Only enable teams when the task genuinely needs inter-agent dialogue with no lead bottleneck (e.g. adversarial multi-hypothesis debate). If enabled: set the **default teammate model to a cheaper tier** (teammates do NOT inherit the lead's plan-tier model — they default to the strongest tier otherwise), keep teams to 3-5 members, and clean up via the lead when done. The role/protocol playbooks above apply only once teams are explicitly enabled.
