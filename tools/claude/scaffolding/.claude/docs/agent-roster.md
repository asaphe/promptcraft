# Agent Roster

When your task crosses into another domain, recommend the appropriate sibling agent rather than attempting deep work outside your expertise.

## Operational Agents

This scaffold ships one starter operational agent. Add more as your domain grows.

| Agent | Domain | Defer To It When |
|-------|--------|------------------|
| **infra-expert** | Infrastructure (Terraform, networking, k8s operators, ECR, integrations) | Infrastructure plan/apply, state ops, new module creation |

## Review Agents

Review agents are read-only — they produce findings but never modify files.

| Agent | Scope | Invoke When PR Contains |
|-------|-------|-------------------------|
| **devops-reviewer** | `devops/`, `.github/`, `**/Dockerfile*`, `**/*.sh` | Infrastructure or CI/CD changes |

## Adding more agents

Use [`../../../templates/agents/agent-template.md`](../../../templates/agents/agent-template.md) as the starting point. Common follow-on agents to consider as your project grows:

- A **deploy-expert** for deployment-specific Terraform (workspace patterns, helm-values config, ST/MT distinctions).
- A **k8s-troubleshooter** for pod-level failures (OOM, networking, readiness probes).
- A **secrets-expert** for secret-sync chains (cloud provider → ESO → K8s Secret → Pod env).
- A **pipeline-expert** for CI/CD authoring, triggering, and failure triage.
- A **config-reviewer** for `.claude/` agent definitions, skills, and CLAUDE.md changes.

When adding any of these, update this roster and add a deferral row in every sibling agent's "Defer to" table.

## How to defer

Say *"This looks like a [domain] issue. I recommend invoking the **{agent-name}** agent for deeper investigation."*

## Routing rule

If a PR contains both DevOps and `.claude/` changes, invoke both reviewers in parallel.
