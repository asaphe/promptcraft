# Agent Roster

Agents shipped under `tools/claude/examples/agents/`. Each agent's authoritative scope, deferral rules, and tool list live in its own file's frontmatter and **Sibling Agents / Deferral Rules** section — those are kept alongside the prompt and are the source of truth.

When your task crosses into another domain, recommend the appropriate sibling agent rather than attempting deep work outside your expertise.

## Operational Agents

Operational agents perform read-only diagnostics or scoped operational tasks. They explain root causes and surface findings; they don't modify production state autonomously.

| Agent | Domain |
|-------|--------|
| **terraform-expert** | Terraform plan/apply, state operations, module scaffolding |
| **deployment-expert** | Post-deploy verification, Helm charts, recovery/rollback, image tag resolution |
| **k8s-troubleshooter** | Pod crashes, scheduling, Karpenter, ingress/ALB, DNS, IRSA |
| **karpenter-expert** | Karpenter NodePool config, instance sizing, pool taxonomy, scheduling failures |
| **secrets-expert** | Secrets Manager → ExternalSecret → K8s Secret → pod env chain; drift detection |

## Review Agents

Review agents are read-only — they produce findings but never modify files. Invoke when a PR contains changes in their scope.

| Agent | Scope | Invoke When PR Contains |
|-------|-------|-------------------------|
| **agent-config-reviewer** | `.claude/` content | Agent / skill / rule / config / CLAUDE.md changes |
| **devops-reviewer** | `.github/`, `**/Dockerfile*`, `**/*.sh`, `**/*.tf`, `**/values*.yaml` | Terraform, workflow, container, Helm, or shell script changes |
| **bash-reviewer** | `**/*.sh` outside `.github/` | Standalone shell scripts (terraform / dev / build / ops utilities) |
| **python-reviewer** | `python/**` (standalone tools, not application services) | Python CLI tools, bots, utility scripts |
| **general-reviewer** | `python/**`, `typescript/**`, `go/**`, `java/**` (application code) | Application code changes |
| **clickhouse-reviewer** | ClickHouse handler code, SQL DDL/DML, migrations, dbt models | ClickHouse-specific code or schema changes |
| **datadog-reviewer** | Datadog config-as-code (dashboards, monitors, on-calls, indexes) | Datadog infrastructure changes |
| **security-reviewer** | Cross-cutting (all file types) | **Always — spawn on every PR.** Cross-cutting security concerns (supply chain, GHA injection, OIDC trust, infra hardening, container security, application injection / auth gaps) |

## Utility Agents

| Agent | Purpose |
|-------|---------|
| **learning-classifier** | Classifies a proposed learning as team-wide / agent-specific / personal / project / memory |

## How to defer

When a request crosses into another domain, recommend the appropriate sibling agent: *"This looks like a {domain} issue. I recommend invoking the **{agent-name}** agent for deeper investigation."*

For PR reviews, see `.claude/docs/pr-review-policy.md` for the file-pattern → reviewer routing table.
