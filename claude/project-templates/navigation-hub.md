# CLAUDE.md - Navigation Hub Template

This directory contains comprehensive guidance for Claude Code (claude.ai/code) when working in your repository.

---

## Documentation Organization

### Core Guides

#### [CODEBASE.md](CODEBASE.md) - Development Workflows & Architecture

Essential guide for daily development work:

- **Essential Commands** - Language-specific commands, build tools
- **Architecture Overview** - Monorepo structure, key patterns
- **Technology Stack** - Languages, frameworks, tools
- **Local Development** - Docker Compose, environment setup
- **Common Workflows** - Adding services, debugging, testing

**Use when:** Starting development, understanding architecture, running commands

#### [specs/ci-cd-spec.md](specs/ci-cd-spec.md) - RFC-Style CI/CD Specification

Comprehensive RFC-style specification for infrastructure and CI/CD:

- **Iron Rules** - Act testing, path validation, naming protocols
- **GitHub Actions Standards** - Workflow development, version pinning
- **Terraform Standards** - Infrastructure as code best practices
- **Docker Standards** - Multi-stage builds, security
- **Validation Protocols** - Linting, testing, quality gates

**Use when:** Modifying GitHub Actions, Terraform, Dockerfiles, bash scripts

---

## Directory-Specific Guides

### [.github/CLAUDE.md](../.github/CLAUDE.md) - GitHub Actions Workflows

Focused guidance for workflow development:

- Mandatory testing protocols (act, path validation)
- Project-specific patterns (change detection, container builds)
- Deployment workflows and security integration
- Cloud provider integration patterns
- Troubleshooting workflows

**Use when:** Working in `.github/workflows/`

### [devops/CLAUDE.md](../devops/CLAUDE.md) - Infrastructure & Kubernetes

Infrastructure and deployment guidance:

- Terraform module organization and standards
- Kubernetes & Helm best practices
- Container standards and registry management
- Cloud resources and IAM patterns
- Monitoring and troubleshooting

**Use when:** Working in `devops/terraform/` or `devops/helm-reusable-chart/`

---

## Cursor IDE Integration

### [.cursor/rules/](../.cursor/rules/) - MDC Format Rules

Project-level rules for Cursor IDE in `.mdc` format:

- `devops-core-principles.mdc` - Core DevOps standards
- `terraform-standards.mdc` - Terraform specific rules
- `github-actions-standards.mdc` - Workflow standards
- `bash-scripting-standards.mdc` - Shell script standards
- `dockerfile-standards.mdc` - Container best practices
- `kubernetes-helm-standards.mdc` - K8s and Helm patterns

**Auto-applied by Cursor IDE** based on file glob patterns

---

## Quick Start

### For New Team Members

1. **Read** [CODEBASE.md](CODEBASE.md) - Understand architecture and development setup
2. **Review** [specs/ci-cd-spec.md](specs/ci-cd-spec.md) - Learn CI/CD standards
3. **Reference** directory-specific guides as needed

### For GitHub Actions Work

1. **Read** [specs/ci-cd-spec.md](specs/ci-cd-spec.md) - Section 2.1 (Act Testing)
2. **Follow** [.github/CLAUDE.md](../.github/CLAUDE.md) - Workflow protocols
3. **Test** with `act` before pushing

### For Infrastructure Work

1. **Read** [specs/ci-cd-spec.md](specs/ci-cd-spec.md) - Section 12.0 (Terraform)
2. **Follow** [devops/CLAUDE.md](../devops/CLAUDE.md) - Module standards
3. **Validate** with `terraform fmt`, `tflint`, `terraform validate`

---

## Key Principles

### Quality First

- Always specify model and confidence level in responses
- Do not leave obvious comments in code
- Follow 12-Factor App design principles where applicable

### Testing & Validation

- Test ALL workflow changes with `act` before implementation
- Validate ALL paths before use - never assume directory structure
- Run appropriate linters and fix all issues before completion

### Security

- Never hardcode secrets, API keys, or sensitive data
- Use proper secret management (cloud-native secret managers, External Secrets Operator)
- Apply principle of least privilege for all access patterns
- Pin versions for reproducibility (actions, base images, providers)

### Naming Conventions

**CRITICAL:** Use only safe, portable identifiers:

- ✅ Valid: `a-zA-Z0-9_` (alphanumeric + underscore)
- ❌ Invalid: hyphens, dots, special characters in identifiers
- Exception: File names can use kebab-case

---

## Technology Stack Example

**Backend Services:**

- Python (Poetry, FastAPI, async frameworks)
- TypeScript/Node.js (pnpm, frameworks, React)
- Java (Maven/Gradle, Spring Boot)
- Go (High-performance services)

**Infrastructure:**

- Cloud Provider (EKS/GKE, Container Registry, Databases, Object Storage, Secret Management)
- Kubernetes (Helm charts, GitOps tools)
- Terraform (Infrastructure modules)
- Docker (Multi-stage builds)

**Databases:**

- PostgreSQL (Multiple logical databases)
- Analytics Database (ClickHouse, BigQuery, etc.)
- Message Queues (RabbitMQ, Cloud-native queues)

---

## Architecture Patterns Example

1. **Event-Driven** - Async communication via message queues
2. **Multi-Database** - Separate logical databases for domains
3. **Microservices** - Multiple services across different languages
4. **Schema-Driven** - JSON schemas as single source of truth
5. **Infrastructure as Code** - All cloud resources via Terraform
6. **GitOps** - Declarative deployments via GitOps tools

---

## Getting Help

- **Codebase Questions** → [CODEBASE.md](CODEBASE.md)
- **CI/CD Standards** → [specs/ci-cd-spec.md](specs/ci-cd-spec.md)
- **Workflow Issues** → [.github/CLAUDE.md](../.github/CLAUDE.md)
- **Infrastructure Issues** → [devops/CLAUDE.md](../devops/CLAUDE.md)
- **Contributing** → See `/CONTRIBUTING.md` in repository root

---

## Document Maintenance

**Primary Maintainer:** DevOps/Platform Team
**Review Frequency:** Quarterly or when major patterns change
**Contribution:** Submit PRs for improvements

---

**Template Version**: 1.0
**Based on**: Real-world monorepo implementation
**Last Updated**: 2025-12-16
