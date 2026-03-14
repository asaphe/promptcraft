# Agent Roster

When your task crosses into another domain, recommend the appropriate sibling agent rather than attempting deep work outside your expertise.

| Agent | Domain | Defer To It When |
|-------|--------|-----------------|
| **terraform-expert** | Non-deployment TF (core, network, ECR, EKS, k8s-operators, integrations, services), module scaffolding, tf-modules repo | Non-deployment TF plan/apply, state ops on infra modules, new module creation, tf-modules updates. For Databricks modules, defer to **databricks-expert** |
| **terraform-deployment-expert** | Deployment TF modules 01-12, ST vs MT patterns, deployment_configs.tfvars, 10-helm-values config | Deployment module plan/apply, workspace patterns, ST/MT behavior, deployment infra failures |
| **pipeline-expert** | Full CI/CD pipeline lifecycle — workflow authoring, triggering, monitoring, troubleshooting | Workflow/action creation or modification, pipeline triggering, run monitoring, CI failures, workflow debugging |
| **deployment-expert** | Post-deploy verification, Helm charts, recovery/rollback, image tags | Post-deploy health checks, Helm issues, deployment recovery, image tag resolution |
| **k8s-troubleshooter** | Pod crashes, scheduling, Karpenter, ingress/ALB, DNS, IRSA | Pod-level failures, OOM, scaling, networking, readiness probes |
| **secrets-expert** | AWS SM → ESO → K8s Secret → Pod env chain; secret tier classification; ST vs MT patterns; IAM path coverage | ExternalSecret sync errors, secret format/tier, drift detection, new secret creation, IAM AccessDenied from ESO |
| **databricks-expert** | Databricks account, workspaces, Unity Catalog, PrivateLink/VPC networking, MWS API, DNS, SCIM | Databricks TF modules, MWS API calls, endpoint migrations, network config, Unity Catalog access, workspace provisioning |
| **data-platform-expert** | Dagster orchestration, dbt, ClickHouse ops/migrations, PostgreSQL/Alembic, ingestion pipeline | Dagster run failures, dbt model/test errors, ClickHouse migration/backup/restore, Alembic failures, ingestion debugging, data quality issues |

**How to defer:** Say *"This looks like a [domain] issue. I recommend invoking the **{agent-name}** agent for deeper investigation."*

## Review Agents

Review agents are read-only — they produce findings but never modify files. Invoke them when a PR contains changes in their scope.

| Agent | Scope | Invoke When PR Contains |
|-------|-------|------------------------|
| **devops-reviewer** | `devops/`, `.github/`, `**/Dockerfile*`, `**/*.sh` | Terraform, workflow, container, or shell script changes |
| **secrets-config-reviewer** | `**/05-external-secrets-stores/vars/`, `**/10-helm-values/vars/`, `**/helm-reusable-chart/values/` | Secret tfvars, helm template secret refs, ExternalSecret configs, naming convention changes |
| **clickhouse-reviewer** | ClickHouse handler code, SQL DDL/DML, migration files, dbt models, CH Terraform | ClickHouse handler code, SQL DDL/DML with MergeTree, migration files, dbt models, CH Terraform |
| **agent-config-reviewer** | `.claude/` | Agent definitions, skill/command definitions, CLAUDE.md, roster, or spec changes |
| **general-reviewer** | `python/**`, `typescript/**`, `go/**`, `java/**` | Python, TypeScript, Go, or Java application code changes |

**Routing rule:** If a PR contains changes across multiple reviewer scopes, invoke all applicable reviewers in parallel.

## Utility Agents

| Agent | Purpose | Invoke When |
|-------|---------|-------------|
| **learning-classifier** | Classifies proposed learnings as team-wide, agent-specific, or personal | A correction or pattern is identified but the right target location is ambiguous |
