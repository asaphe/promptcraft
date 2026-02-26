# Architecture Reference

On-demand reference — read when you need to understand directory structure, service boundaries, or databases.

## Repository Structure

```text
.
├── python/                    # Python services
│   ├── <api-service>/        # REST API (FastAPI)
│   ├── <worker-service>/     # Celery worker
│   └── <data-pipeline>/      # Data processing pipelines
├── typescript/                # TypeScript monorepo
│   ├── apps/
│   │   ├── <web-app>/       # React SPA
│   │   └── <api-server>/    # Node.js API
│   └── packages/             # Shared packages
├── java/                      # Java services
│   └── <workflow-engine>/    # Workflow orchestration
├── go/                        # Go services
│   └── <event-processor>/   # Event stream processing
├── devops/                    # Infrastructure
│   ├── terraform/            # ~30 Terraform modules
│   ├── helm-chart/           # Reusable Helm chart
│   └── docker/               # Dockerfiles
└── .github/                   # CI/CD workflows
```

## Services

| Service              | Language   | Type             | Port | Database               |
| -------------------- | ---------- | ---------------- | ---- | ---------------------- |
| `<api-server>`       | TypeScript | REST API         | 3000 | PostgreSQL             |
| `<web-app>`          | TypeScript | SPA              | 8080 | None                   |
| `<api-service>`      | Python     | REST API         | 8000 | PostgreSQL             |
| `<worker-service>`   | Python     | Celery Worker    | N/A  | PostgreSQL, Redis      |
| `<data-pipeline>`    | Python     | Batch Jobs       | N/A  | PostgreSQL, ClickHouse |
| `<workflow-engine>`  | Java       | Workflow         | 8081 | PostgreSQL             |
| `<event-processor>`  | Go         | Stream Processor | N/A  | ClickHouse             |

## Databases

| Database             | Type        | Usage                                            |
| -------------------- | ----------- | ------------------------------------------------ |
| PostgreSQL (RDS)     | Relational  | Application data, tenant configs, workflow state |
| ClickHouse           | Columnar    | Analytics, event storage, aggregations           |
| Redis (ElastiCache)  | Cache/Queue | Celery broker, session cache, rate limiting      |

## Multi-Tenant Data Isolation

- PostgreSQL: schema-per-tenant isolation
- ClickHouse: tenant column filtering
- All queries must include tenant context
- API middleware validates tenant ownership on every request
