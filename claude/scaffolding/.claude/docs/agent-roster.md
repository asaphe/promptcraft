# Agent Roster

When your task crosses into another domain, recommend the appropriate sibling agent rather than attempting deep work outside your expertise.

| Agent                  | Domain                                                                     | Defer To It When                                          |
| ---------------------- | -------------------------------------------------------------------------- | --------------------------------------------------------- |
| **infra-expert**       | Non-deployment TF (core, network, ECR, EKS, k8s-operators, integrations)   | Infrastructure plan/apply, state ops, new module creation |
| **deploy-expert**      | Deployment TF modules 01-10, helm-values config, workspace patterns        | Deployment plan/apply, ST/MT behavior, deployment infra   |
| **pipeline-expert**    | CI/CD pipeline lifecycle — workflow authoring, triggering, monitoring      | Workflow creation, pipeline triggering, CI failures       |
| **k8s-troubleshooter** | Pod crashes, scheduling, scaling, ingress/ALB, DNS                         | Pod-level failures, OOM, networking, readiness probes     |
| **secrets-expert**     | Secret sync chain (cloud provider -> ESO -> K8s Secret -> Pod env)         | Secret sync errors, format, drift detection, IAM access   |

**How to defer:** Say *"This looks like a [domain] issue. I recommend invoking the **{agent-name}** agent for deeper investigation."*

## Review Agents

Review agents are read-only — they produce findings but never modify files.

| Agent                | Scope                                              | Invoke When PR Contains                      |
| -------------------- | -------------------------------------------------- | -------------------------------------------- |
| **devops-reviewer**  | `devops/`, `.github/`, `**/Dockerfile*`, `**/*.sh` | Infrastructure or CI/CD changes              |
| **config-reviewer**  | `.claude/`                                         | Agent definitions, skills, CLAUDE.md changes |

**Routing rule:** If a PR contains both DevOps and `.claude/` changes, invoke both reviewers in parallel.
