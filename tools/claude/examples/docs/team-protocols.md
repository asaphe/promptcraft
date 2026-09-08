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

There is no manual create or delete step, and no `TeamCreate` / `TeamDelete` tool to call — older write-ups that describe one are describing a lifecycle that no longer exists. Check your own tool list before following any instruction that names them.

1. **Spawn** — describe the task and the teammates you want in natural language, or name a specific subagent type ("spawn a teammate using the `security-reviewer` agent type to…"). The team forms implicitly when the first teammate spawns, with the current session as lead, and it is named after the session — you do not get to choose the name.
2. **Assign work** — a shared task list via the built-in task tools, or direct messages.
3. **Coordinate** — members communicate with each other; the lead watches the agent panel or the split panes.
4. **Collect results** — members send findings to the lead; an idle teammate auto-notifies the lead when it stops.
5. **Shut down** — before ending the turn, explicitly tell every named teammate to shut down. Do this even when the task looks finished, and do not assume the harness cleans up unprompted (see the gotchas below).

One team per session, scoped to that session's lifetime: no cross-session or reusable named teams, and no sub-teams spawned by a teammate. Like everything else in this file, that was established by using the feature rather than read out of a spec — confirm it against your own version before designing around it.

### `SendMessage` schema

The schema is `additionalProperties: false`, so plausible-looking parameters — `type`, `recipient`, `content` — are *rejected* rather than silently ignored. On Claude Code 2.1.263 it accepts `to`, `message`, `summary` and `notify_when_idle`, of which only `to` and `message` are required; `summary` is a short label for your own transcript and is truncated rather than rejected if it runs long.

The general point outlives the specific field list: **read a deferred tool's schema before the first call instead of guessing it from the name.** The shape drifts between versions — the required set here has already changed once — and a strict schema turns a plausible guess into a hard failure rather than a tolerated extra key.

### Gotchas

Each of these was observed in practice rather than read out of a changelog, and several have survived multiple releases. Re-check any one you are about to depend on — the feature is still experimental and the behavior moves.

- **Permission mode is inherited from the lead at spawn and cannot be set per teammate.** If the lead runs in plan mode, every teammate starts in plan mode and must get a plan approved before touching a file. Harmless for research and review teammates; for implementation teammates, budget a plan-approval round-trip each. This is separate from the explicit "require plan approval" feature, which stacks on top of the lead's base mode.
- **No session resumption for in-process teammates** — `/resume` and `/rewind` do not restore them. After a resume, respawn rather than messaging a stale teammate name.
- **No nested teams and no background subagents from a teammate** — a teammate cannot spawn its own sub-team, and any subagent it launches runs in the foreground, since it cannot outlive the lead's process.
- **Task status can lag** — teammates sometimes fail to mark a task complete, which blocks dependents. Check actual state rather than the board.
- **An idle notification can arrive without the output ever being delivered.** This applies to plain `Agent`-tool spawns too, not just full teammates: a reviewer fan-out goes idle having delivered zero findings text. Recovery is one message re-requesting the report; if it goes idle a second time with nothing delivered, stop it and do the work inline — a third attempt is not worth the wait.
- **A teammate spawned from a named subagent type may not have `SendMessage` in its callable tool list at all**, even though its system prompt describes messaging as the teammate-communication mechanism. The cause is upstream in your own definitions: agent files authored for plain `Agent`-tool use list only the tools needed to produce a *return value*, and the "reuse a subagent role as a teammate" mechanism carries that narrow allowlist over verbatim. The failure is intermittent — the same agent type and the same version produce both outcomes — and its signature is an idle teammate whose team inbox files are empty arrays, with the report present only as turn output. Two mitigations: add `SendMessage` to `tools:` in any definition you intend to spawn as a named teammate, and have a `PreToolUse: Agent` hook warn when a named spawn uses a type whose definition lacks it.
- **Teammate permission prompts bubble up to the lead** — pre-approve routine operations before spawning, or the lead spends the session answering prompts.
- **Auto-cleanup on session end is unreliable.** `~/.claude/teams/session-*/` directories have been observed surviving long after their session ended, including cases where teammates kept writing to team state hours after the lead's transcript went idle. Shut teammates down explicitly, and audit `~/.claude/teams/` by hand: cross-check each `config.json` against whether its lead session's transcript is still being written to, and delete the directory if that transcript is dead.
- **Every session pays a scaffold cost whether or not you use teams.** With the feature flag on, a `session-<id>/config.json` holding a solitary `team-lead` entry is created per session even when no teammate is ever spawned — so a team-lead-only directory is not evidence that a team was used.

## Design Principles

- **Agents stay as-is** — `.claude/agents/*.md` files define domain expertise. Teams compose agents, not replace them.
- **Deferral rules stay** — Agents still know their boundaries. Teams just make handoffs faster.
- **Solo spawning is default** — Teams are opt-in for multi-domain work.
- **Read-only agents stay read-only** — No file conflict risk in review teams.
- **Team members need full context** — Subagents don't inherit parent context. Include all necessary instructions and file references in the spawn prompt.

## Teams are a deliberate escalation (policy gate)

Agent teams spawn full peer agent instances and can cost several times the tokens of a single session (especially when teammates run a planning model). Keep them disabled by default and reach for subagent fan-out or a decision-panel skill instead.

Only enable teams when the task genuinely needs inter-agent dialogue with no lead bottleneck (e.g. adversarial multi-hypothesis debate). If enabled: **set the default teammate model explicitly** rather than assuming a teammate inherits the lead's — check what a spawned teammate actually resolves to before sizing the cost, since the default has not always been the cheap one. Keep teams to 3-5 members, and clean up via the lead when done. The role/protocol playbooks above apply only once teams are explicitly enabled.
