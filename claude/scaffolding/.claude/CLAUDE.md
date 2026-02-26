# CLAUDE.md

Full-stack SaaS monorepo — data pipelines (Python), web UI + API (TypeScript), workflow engine (Java), event processor (Go), and ~30 Terraform modules. Trunk-based development on `main`.

## On-Demand Reference (read when relevant)

- **Building, testing, or running services?** Read `.claude/docs/build-commands.md`
- **Need to understand directory structure, modules, or databases?** Read `.claude/docs/architecture.md`
- **Working on GitHub Actions, Terraform, Dockerfiles, or bash scripts?** Read `.claude/specs/ci-cd-spec.md`

## Specialized Agents

Seven specialist agents handle domain-specific tasks — 5 operational and 2 review agents. See `.claude/docs/agent-roster.md` for full boundaries and deferral rules.

| Agent                  | When to Use                                                       |
| ---------------------- | ----------------------------------------------------------------- |
| **infra-expert**       | Non-deployment TF: VPC, EKS, operators, ECR, integrations         |
| **deploy-expert**      | Deployment TF (modules 01-10): workspaces, helm-values, configs   |
| **k8s-troubleshooter** | Pod crashes, OOM, scheduling, networking, probes                  |
| **secrets-expert**     | ExternalSecret sync, secret format, drift detection               |
| **pipeline-expert**    | Workflow/action authoring, pipeline triggering, CI failures       |

### Review Agents

| Agent                | When to Use                                                        |
| -------------------- | ------------------------------------------------------------------ |
| **devops-reviewer**  | PR review of Terraform, GitHub Actions, Dockerfiles, shell scripts |
| **config-reviewer**  | PR review of `.claude/` agent definitions, skills, CLAUDE.md       |

## Code Standards

- **Never use `Any` type** — always be explicit
- **Use `| None` instead of `Optional`** in Python
- All API models use Pydantic; strict TypeScript
- FastAPI for APIs (async), Celery workers (synchronous)
- Repository pattern, Pydantic models, official SDKs over raw HTTP
- Functional components, React hooks, TailwindCSS
- Group imports: external/internal, alphabetized
- Conventional commits: `feat:`, `fix:`, `refac:`, etc.
- **Branch names must follow `dev-###-short-description`.** If the branch doesn't match this pattern, flag it and ask.

## Multi-Tenant Architecture

- Tenant-scoped data access, PostgreSQL schema-based isolation
- Always validate tenant ownership; platform instances are tenant-specific

## DevOps Standards

- Pin ALL versions (never `latest`), multi-stage Docker builds
- Shell scripts: `shellcheck`, Dockerfiles: `hadolint`, Terraform: `fmt` + `tflint`

## Operational Rules (`.claude/rules/`)

Auto-loaded rules from past operational experience live in `.claude/rules/`. These are always in context.

When you encounter a correction, failure, or unexpected behavior during a session, proactively propose capturing it as a rule. Classify: agent-specific -> agent definition, team-wide -> `.claude/rules/`. Format each rule as a single bullet: `- **Rule title** — What to do and why.`

## Subdirectory CLAUDE.md Files

These load automatically when working in the respective directories:

- `typescript/CLAUDE.md` — TypeScript monorepo (apps, packages)
- `python/CLAUDE.md` — Python services and workers
- `devops/CLAUDE.md` — Terraform standards, Helm, containers, AWS
- `devops/terraform/CLAUDE.md` — Terraform module index and lookup
- `.github/CLAUDE.md` — GitHub Actions project patterns
