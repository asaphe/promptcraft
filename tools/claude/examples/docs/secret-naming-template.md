# Secret Naming Convention (template)

> **When this convention fits:** use this if (a) your system is multi-tenant and / or has multiple deployments, (b) you have a clear separation between globally-shared secrets and per-deployment / per-tenant secrets, and (c) you store secrets in AWS Secrets Manager (or a similar path-keyed store). Single-tenant single-app systems don't need this layered structure — a flat `app/<name>` keyspace is fine. The `discovery_key` segment (covered below) is an advanced add-on that only pays off if you also build a dynamic discovery layer; skip it otherwise.

A hierarchical secret-path convention for systems that span multiple tenants and deployments. Standardizes paths so:

- Audits can answer "what secrets exist for application / tenant / environment X" by listing a known prefix
- Least-privilege IAM policies can use predictable resource ARNs without overly broad wildcards
- Auto-discovery can pull secrets dynamically without hardcoded paths
- Operators can tell at a glance whether a secret is shared globally or scoped to a specific tenant

## Two patterns, three tiers

### Global secrets — shared across all tenants and deployments

```text
global/{team|application}/{environment?}/{secret_name}
```

| Segment | Required | Description |
|---|---|---|
| `global` | yes | Fixed prefix identifying shared secrets |
| `team` / `application` | yes | Owning team or consuming application |
| `environment` | no | `prod` or `stg` — omit when env-agnostic |
| `secret_name` | yes | Descriptive name (e.g. `resend`, `intercom`, `slack`) |

**Examples:**

| Path | Description |
|---|---|
| `global/app-server/prod/resend` | Resend API key for app-server in prod |
| `global/webapp/prod/intercom` | Intercom credentials for webapp in prod |
| `global/<team>/slack` | Slack credentials shared across all envs (no environment segment) |

### Per-deployment / per-tenant secrets

Scoped to a specific deployment, and optionally to a specific tenant within that deployment.

```text
{env}/{deployment}/{secret_path}
{env}/{deployment}/{tenant}/{discovery_key}/{secret_name}
```

| Segment | Required | Description |
|---|---|---|
| `env` | yes | Environment: `prod`, `stg`, or similar |
| `deployment` | yes | Deployment identifier |
| `tenant` | for tenant-scoped | Tenant name within the deployment |
| `discovery_key` | for discovered | Team / application scope used by auto-discovery |
| `secret_name` | yes | Service or resource name, may include sub-paths |

**Examples:**

| Path | Description |
|---|---|
| `prod/<deployment>/descope` | Auth provider creds for a deployment |
| `prod/<deployment>/rds/applications/app_server` | RDS creds for app-server within the deployment |
| `prod/<deployment>/<tenant>/clickhouse/app_server` | ClickHouse creds for one tenant inside the deployment |
| `stg/<deployment>/<tenant>/<team>/<integration>/{uuid}` | Per-tenant external-integration credentials |

## Why two patterns and not one

Global secrets that vary by environment but not tenant (Resend, Intercom, Slack) need a 3-segment structure. Per-tenant secrets (RDS user / password, ClickHouse credentials per tenant, OAuth-app integrations bound to a single tenant) need a deeper structure with the `tenant` and `discovery_key` segments.

Forcing both into one shape either bloats global paths with unused tenant segments, or hides tenant scope when it's load-bearing for IAM policy.

## Token substitution in IaC

In Terraform tfvars, parameterize secret paths with placeholders so the same template renders correctly per environment / deployment / tenant:

| Token | Resolves to | Example |
|---|---|---|
| `<GLOBAL_SECRET_PREFIX>` | `global` (always) | `global` |
| `<GLOBAL_ENV>` | `prod` / `stg` | `prod` |
| `<DEPLOYMENT>` | deployment name | `acme-prod` |
| `<TENANT_NAME>` | tenant identifier (per-tenant only) | `customer-1` |

Resolution happens once in `locals_tokens.tf` (or equivalent) — application code never sees the raw tokens.

## Discovery key (advanced add-on)

> Skip this section if you don't build a dynamic discovery layer.

The `{discovery_key}` segment in tenant-scoped paths enables auto-discovery: a Helm-values renderer (or equivalent) can list all secrets under `{env}/{deployment}/{tenant}/{discovery_key}/` and inject them into the consuming pod's environment without hardcoding individual secret names. Adding a new integration becomes "create the secret at the right path" — no IaC change needed for the consuming workload.

The trade-off: dynamic discovery makes "what does this pod read" harder to answer from code alone. Document the discovery convention near the consuming workload's deployment manifests. If you don't have (or want) a discovery layer, use the simpler `{env}/{deployment}/{tenant}/{secret_name}` shape directly.

## IAM policy templates

The two patterns enable per-tier IAM scoping:

```hcl
# Global secrets — read access for an application
"Resource": "arn:aws:secretsmanager:*:*:secret:global/<application>/*"

# Per-deployment secrets — read access for a deployment's role
"Resource": "arn:aws:secretsmanager:*:*:secret:<env>/<deployment>/*"

# Per-tenant secrets only — for tenant-scoped runtimes
"Resource": "arn:aws:secretsmanager:*:*:secret:<env>/<deployment>/<tenant>/*"
```

Avoid wildcards that span tiers (e.g., `*/*/clickhouse/*`) — they grant access to other tenants' secrets by accident. The path structure was designed to make tier boundaries explicit.

## Migration from organic paths

When migrating from organically-grown secret paths:

1. Audit existing paths: `aws secretsmanager list-secrets --query 'SecretList[].Name' --output text | tr '\t' '\n' | sort`
2. Map each to the new tier (global / per-deployment / per-tenant)
3. Create new secrets at the conventional paths; update consumers to read from the new path; verify; delete old paths only after consumer migration is complete and a soft-deletion grace period has passed
4. Update IaC modules to generate paths via the convention going forward
5. Add a CI lint that rejects new secrets created outside the convention
