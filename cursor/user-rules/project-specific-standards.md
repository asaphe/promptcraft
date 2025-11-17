# Project-Specific Infrastructure Standards

> **Context**: These standards apply specifically to infrastructure projects. These are organizational conventions and patterns that should be followed when working on infrastructure code, Terraform modules, Helm charts, and CI/CD pipelines.

## Terraform Standards

### Structure

- Use numbered prefixes for infrastructure layers (00-core, 01-network, 02-dns, etc.)
- Maintain clear separation between foundational (00-05) and application-specific (99-) infrastructure
- Use `#template` directory for standardized module scaffolding
- Always include `backend.tf`, `providers.tf`, `variables.tf`, and `versions.tf` in each module

### State Management

- Use S3 backend
- Enable encryption and use DynamoDB for state locking ("terraform-state-locking")
- Use Terraform workspaces for environment and service separation
- Follow workspace naming: `{env}-{service}-{region}` or `{env}_{tenant}-{service}`

### Cross-Account Access

- Use dedicated IAM role "terraform-state" for state management
- Configure cross-account access between dev (724772095192) and prod (861276082564)
- Use SSO administrator roles and GitHub Actions roles for access

### Code Quality

- Run `terraform fmt -recursive` before commits
- Use tflint with central config (`.tflint.hcl`) for code quality
- Pin Terraform version using `.terraform-version` file

### Variables

- Use environment-specific `.tfvars` files (`dev.tfvars`, `prod.tfvars`, `root.tfvars`)
- Always include `aws_region`, `aws_profile`, and `cidr_blocks` variables
- Use consistent EKS addon versioning and configuration patterns

## Helm Standards

### Chart Structure

- Use single reusable chart with tenant-specific values overrides
- Organize values by: `devops/helm-reusable-chart/values/{tenant}/{service}.yaml`
- Support multi-tenancy (cushman, emerson, sixt) with service-specific configurations

### Service Configuration

- Default resources: 250m CPU / 256Mi memory requests, 500m CPU / 512Mi memory limits
- Use ClusterIP services with port 8080 default
- Enable probes with `/health` endpoint by default
- Use gp3 storage class for persistent volumes

### Security Patterns

- Create service accounts with EKS IAM role annotations
- Use External Secrets Operator for secret management
- Follow format: `arn:aws:iam::{account}:role/{env}-eks-01-{service}-{tenant}`
- Enable Datadog logging annotations for observability

### Scaling Configuration

- Choose between KEDA (event-driven) or HPA (metrics-based) scaling
- Default HPA: 1-1 replicas, 80% CPU utilization threshold
- Configure Pod Disruption Budgets for production services

## GitHub Actions Standards

### Workflow Patterns

- Use path-based change detection with `dorny/paths-filter`
- Implement matrix builds for multi-language/multi-service repositories
- Use concurrency groups to prevent overlapping deployments
- Employ self-hosted runners for resource-intensive tasks

### Container Workflow

- Auto-create ECR repositories via Terraform during container builds
- Use multi-stage builds with BuildKit caching (`type=gha`)
- Apply consistent tagging: branch, PR, SHA, semantic versions
- Run Hadolint for Dockerfile linting before builds

### Deployment Workflow

- Use manual dispatch with environment/tenant/application parameters
- Create/select Terraform workspaces dynamically based on inputs
- Plan before apply with approval gates for production
- Generate deployment summaries in GitHub Actions summary

### Security Integration

- Run Amazon Inspector vulnerability scans on repository
- Use Gitleaks for secret scanning with custom configuration
- Configure vulnerability thresholds (critical: 1, high: 1, medium: 3)
- Implement GitOps approval workflows for production deployments

## Language Standards

### Change Detection

- Detect changes per language/service: `python_*`, `typescript_*`, `java`, `go`
- Run language-specific linting, testing, and building only on changes
- Use shared common modules as dependencies between services

### Build Matrix

- Define context, dockerfile, and path_filter for each service
- Map services to container repositories consistently
- Use language-specific base images and build patterns

### Testing Strategy

- Run unit tests per changed module with isolated environments
- Include E2E tests for UI applications (Playwright)
- Use AWS credentials for integration testing in dev environment
- Cache dependencies (Poetry, pnpm, Go modules, Maven) across builds

## Tenant Isolation

### Configuration Separation

- Use tenant-specific Helm values files for service configuration
- Configure tenant-specific SQS queues, databases, and storage paths
- Apply tenant-specific IAM roles and security policies
- Use environment variables for tenant-specific resource naming

### Resource Scaling

- Configure tenant-specific resource requests/limits based on usage
- Use tenant-specific database connections and schemas
- Apply tenant-specific monitoring and logging configurations
- Scale replicas based on tenant workload requirements

### Deployment Isolation

- Use Kubernetes namespaces for tenant separation
- Deploy tenant-specific service instances with isolated resources
- Configure tenant-specific ingress rules and external endpoints
- Maintain tenant-specific backup and disaster recovery procedures

## Security Standards

### Access Control

- Use OIDC for GitHub Actions AWS authentication
- Implement least-privilege IAM policies for service roles
- Use AWS Secrets Manager for database credentials and API keys
- Apply workload identity patterns for pod-to-AWS service communication

### Secret Management

- Never hardcode secrets in configuration files or containers
- Use External Secrets Operator to sync secrets into Kubernetes
- Rotate secrets regularly and use automated secret injection
- Mask sensitive values in CI/CD logs and outputs

### Compliance Scanning

- Run daily Gitleaks scans for secret detection
- Implement container vulnerability scanning with Amazon Inspector
- Apply security linting for Terraform (tflint) and containers (Hadolint)
- Use security-focused base images and dependency scanning
