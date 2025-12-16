# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

---

## <COMPANY> SERVICES CODEBASE GUIDE

**Technology Stack:** Python 3.12.8, TypeScript/Node.js 22+, Java 21, Go
**Architecture:** Event-driven microservices on AWS EKS
**Infrastructure:** Terraform, Kubernetes, Docker

---

## Essential Commands

### Python Development

```bash
# Setup (from python/ directory)
poetry install

# Run tests for specific modules
poetry run pytest <ingestion_db>/tests
poetry run pytest assets/tests -v
poetry run pytest mapping/tests -k "test_specific"

# Run single test
poetry run pytest <ingestion_db>/tests/test_foo.py::test_specific_function -v

# Linting
poetry run ruff check .
poetry run ruff format .
poetry run mypy <module>/

# Build wheel for deployment
cd <module> && poetry build
```

### TypeScript Development

```bash
# Setup (from typescript/ directory)
pnpm install

# Start complete dev environment
pnpm prep    # Start infra + workflow engine
pnpm dev     # Start <app-service> (3000) + <web-app> (5173)

# Run specific service
pnpm dev --filter <web-app>
pnpm dev --filter <app-service>

# Tests
pnpm test                                    # All unit tests
pnpm --filter=<web-app> test:e2e               # E2E tests
pnpm --filter=<web-app> test:e2e tests/e2e/login.test.ts  # Single E2E test

# Type checking & linting
pnpm check-types
pnpm lint
pnpm format

# Database operations (from apps/<app-service>/)
pnpm db:migrate:dev
pnpm db:generate-inferred-schemas:dev
```

### Build All Components

```bash
# From repository root
make build                  # Everything
make build_all_wheels       # Python packages
make build_all_typescript   # TS apps
make build_all_dockerfiles  # Docker images
make lint                   # All linters
```

### Local Development Stack

```bash
# Option 1: Docker Compose (from dev-infra/)
docker compose up -d                          # Infrastructure only
docker compose --profile app up -d            # + Application services
docker compose --profile ai up -d             # + AI services
docker compose logs -f <service-name>

# Option 2: TypeScript pnpm (from typescript/)
pnpm prep    # Starts: Postgres, ClickHouse, LocalStack, RabbitMQ, Temporal, Workflow Engine
pnpm dev     # Starts: <app-service>, <web-app>
pnpm down    # Cleanup
```

### Kubernetes (Production/Staging)

```bash
# Configure access
aws eks update-kubeconfig --region us-east-1 --name <env>-eks-<id> --alias <env>-eks-<id>

# Set namespace
kubectl config set-context --current --namespace=<namespace>

# View logs
kubectl logs -f deployment/<app-service>
kubectl logs -f deployment/agents-mesh --tail=100

# Port forwarding
kubectl port-forward svc/<app-service> 3000:3000
```

---

## Architecture Overview

### Monorepo Structure

```text
services/
├── python/              # Backend services (FastAPI, Dagster, Celery, Temporal)
│   ├── adk/            # Asset Development Kit
│   ├── assets/         # Dagster data pipelines
│   ├── agents/         # AI agents
│   ├── <agents_mesh>/    # AI orchestration (Temporal workflows)
│   ├── <ingestion_db>/      # Data <ingestion_db> services
│   ├── <ingestion_db>_api/  # Ingestion REST API
│   ├── mapping/        # Data transformation
│   ├── tasks/          # Celery task orchestration
│   ├── <action_service>/     # Action execution
│   ├── <config_service>/
│   ├── <webhook_service>/
│   └── common/         # Shared utilities
│
├── typescript/         # Frontend & Node.js services
│   ├── apps/
│   │   ├── <web-app>/         # React frontend (port 5173)
│   │   ├── <app-service>/     # NestJS API (port 3000)
│   │   └── workflow-debug-*
│   └── packages/
│       ├── <app-service>-api-client/
│       ├── fwl-transpiler/
│       └── [shared configs]
│
├── java/modules/workflow-engine/  # Flowable workflow runtime (port 8080)
├── go/apps/mapper_sink/           # High-performance data sink
├── devops/terraform/              # Infrastructure as Code (40+ modules)
└── dev-infra/                     # Local docker-compose
```

### Key Architectural Patterns

#### 1. Event-Driven Communication (SQS Queues)

- `<insight-queue>` - AI insights → frontend
- `<agent-to-app-queue>` / `<app-to-agent-queue>` - Agent communication
- `<workflow-events-queue>` - Workflow state changes
- `<mesh-requests-queue>/responses.fifo` - AI mesh orchestration
- `<action-results-queue>` - Action execution results

#### 2. Multi-Database Strategy

- **PostgreSQL (separate logical databases):**
  - `<app_db>` - Application data
  - `<domain_db>` - Identity <domain_db> graph
  - `<workflow_db>` - Workflow engine state
  - `<ingestion_db>` - Ingestion metadata
  - `<config_db>` - Tenant configuration
  - `<sessions_db>` - AI sessions
- **ClickHouse:** Analytics and time-series events

#### 3. Python Workspace Model

- Single `.venv` in `python/` directory
- Root `pyproject.toml` defines all modules as path dependencies
- Enables direct imports: `from common.logging import get_logger`

#### 4. Schema-Driven Development

- JSON schemas in `resources/event_schemas/`, `resources/insights/`, `resources/goals/`
- Code generation: Python (Pydantic), TypeScript (Zod), Java (POJOs)
- Single source of truth prevents schema drift

#### 5. Terraform Module Organization

- Numbered prefixes indicate deployment order: `00-core/`, `04-ecr/`, `06-eks/`, etc.
- Modular, reusable infrastructure components
- ~40 modules for complete AWS setup

---

## Important Context

### Python Package Dependencies

Modules depend on each other via Poetry workspace:

- `assets` → `adk`, `common`, `<domain_db>_base_db`
- `<ingestion_db>` → `common`, `storage_sdk`, `<domain_db>_base_db`
- `tasks` → `<ingestion_db>`, `common`, `storage_sdk`

Changes to `common/` or `<domain_db>_base_db/` affect many downstream modules.

### TypeScript Turborepo

Build pipeline with dependency tracking:

- Changes to `packages/*` trigger rebuilds of dependent `apps/*`
- `pnpm build` uses Turborepo caching
- Use `--force` flag to bypass cache when needed

### CI/CD Smart Detection

GitHub Actions use `dorny/paths-filter` to detect changes:

- Only affected services are tested/built
- Parallel execution where possible
- Example: Python <ingestion_db> change → only `<ingestion_db>_api` container rebuilt

### Environment Variables

**Python services:** `devops/docker-compose/envs/pathid.env`, `devops/envs/local-deployment.env`
**TypeScript services:** `typescript/apps/*/. env.development`

Key variables:

- `DATABASE_URL` - Postgres connection
- `FABRIC_DATABASE_URL` - Identity <domain_db> DB
- `CLICKHOUSE_URL` - Analytics DB
- `LOCALSTACK_ENDPOINT` - AWS emulation (local dev)
- `DISABLE_EVENT_QUEUES=true` - Simplify local dev

### Code Quality Standards

**Python:**

- PEP8 style (88 char line length)
- Type hints required
- ruff for linting, mypy for type checking
- pytest with async support

**TypeScript:**

- Strict mode enabled
- Avoid `any` type
- ESLint + Prettier
- Vitest (unit), Playwright (E2E)

**Java:**

- Standard naming conventions
- Maven for builds
- JUnit tests

**Commits:**

- Conventional commits format: `feat(scope): description`, `fix(scope): description`
- Branch naming: `dev-###-short-description` (lowercase)
- PRs: Keep under 200 lines when possible

---

## Common Workflows

### Adding a New Python Service

1. Create module: `mkdir python/my_service && cd python/my_service`
2. Initialize: `poetry init`
3. Add to workspace in `python/pyproject.toml`:

   ```toml
   my_service = { path = "my_service", develop = true }
   ```

4. Create Dockerfile (reference existing services)
5. Add Makefile target for wheel build
6. Add to `.github/workflows/container.yaml`
7. Create Terraform deployment module

### Debugging Production Issues

**Check logs:**

```bash
kubectl logs -f deployment/<service-name>
kubectl logs deployment/<service-name> --previous  # Previous container
```

**Access database:**

```bash
# Port forward
kubectl port-forward svc/postgres 5432:5432

# Connect
psql -h localhost -U pathAdmin -d <app_db>
```

**Check queues:**

```bash
# Via LocalStack (local)
aws --endpoint-url=http://localhost:4566 sqs list-queues

# Via AWS (production)
aws sqs list-queues --region us-east-1 --profile prod
```

### Running Single Test

**Python:**

```bash
poetry run pytest path/to/test.py::test_function_name -v -s
```

**TypeScript:**

```bash
pnpm --filter=<web-app> test path/to/test.test.ts
```

**E2E:**

```bash
cd typescript/apps/<web-app>
pnpm test:e2e tests/e2e/specific.test.ts --debug
```

---

## Critical Integration Points

### Python ↔ TypeScript

- Schema validation at API boundaries
- Python services publish SQS events → TypeScript consumes
- TypeScript <app-service> calls Python REST APIs

### TypeScript ↔ Java

- App-server creates workflows via Flowable REST API (port 8080)
- Workflow engine publishes state changes to SQS
- App-server consumes workflow events

### All Services ↔ Databases

- PostgreSQL: Multiple logical databases for domain separation
- ClickHouse: High-volume analytics and time-series
- Connection pooling configured per service

---

## Common Pitfalls

1. **Forgetting AWS ECR authentication** - Required for workflow engine Docker builds:

   ```bash
   aws sso login --profile prod
   aws ecr get-login-password --region us-east-1 --profile prod | docker login --username AWS --password-stdin <AWS_ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com
   ```

2. **Wrong database connection** - Multiple Postgres databases with different purposes (check DATABASE_URL)

3. **Poetry virtual env issues** - Always verify: `which python` (should be `python/.venv/bin/python`)

4. **Turborepo cache stale** - Use `pnpm build --force` to bypass cache

5. **Missing environment variables** - Check `.env.development` files exist and are populated

---

## Additional Resources

- `/docs/installations.md` - Development environment setup
- `/docs/aws_credentials.md` - AWS SSO configuration
- `/docs/deployment-workflows.md` - Deployment process
- `/CONTRIBUTING.md` - Git workflow and standards
- `python/pyproject.toml` - Workspace configuration and linting rules
- `typescript/turbo.json` - Build pipeline configuration
