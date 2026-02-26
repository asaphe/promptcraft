# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with DevOps infrastructure code in this repository.

---

## <COMPANY> DEVOPS INFRASTRUCTURE GUIDE

## Directory Structure

```text
devops/
├── terraform/              # Infrastructure as Code (~40 modules)
│   ├── 00-core/           # VPC, networking, foundational
│   ├── 04-ecr/            # Container registry
│   ├── 06-eks/            # Kubernetes cluster
│   ├── 99-temporal/       # Workflow orchestration
│   ├── 100-*/             # Shared resources
│   └── deployment/        # Service-specific deployments
├── helm-reusable-chart/   # Kubernetes deployment templates
├── containers/            # Container configurations
├── ecr-image-manifest.yaml  # ECR repository definitions
└── gitleaks.toml          # Secret detection config

```

---

## Terraform Standards

### Module Organization

**Numbered prefixes indicate deployment order:**

- `00-*` - Core infrastructure (VPC, networking)
- `04-*` - Container registry setup

- `05-*` - Pull-through cache

- `06-*` - Kubernetes and auto-scaling

- `07-*` - Load balancers

- `08-*` - GitOps (ArgoCD)
- `09-*` - Monitoring (Datadog)
- `99-*` - Application infrastructure

- `100-*` - Shared resources

- `deployment/` - Service-specific resources

### Standard File Structure

Each module MUST have:

```text
module-name/
├── backend.tf         # S3 backend configuration
├── providers.tf       # Provider configuration
├── main.tf           # Primary resources
├── variables.tf      # Input variables
├── outputs.tf        # Output values
├── data.tf           # Data sources (if needed)
├── locals.tf         # Local values (if needed)
├── .terraform-version # TFEnv version file
└── README.md         # Module documentation

```

### Backend Configuration Standard

**ALWAYS use this backend pattern:**

```terraform
terraform {
  backend "s3" {
    bucket               = "<org>-terraform-state"
    workspace_key_prefix = "module-category/module-name"
    key                  = "terraform.tfstate"
    region               = "us-east-1"
    encrypt              = true
    use_lockfile         = true
    dynamodb_table       = "terraform-state-lock"

    assume_role = {
      role_arn = "arn:aws:iam::<AWS_ACCOUNT_ID>:role/<state-access-role>"
    }
  }
}

```

**Key Points:**

- `workspace_key_prefix` organizes state files by category/purpose

- `key = "terraform.tfstate"` is consistent across all modules

- State file S3 path: `s3://bucket/{workspace_key_prefix}/{workspace}/terraform.tfstate`
- Workspaces enable environment/tenant separation

### Workspace Naming Conventions

**Patterns:**

- **Environment-based**: `{env}-{service}-{region}` (e.g., `prod-eks-us-east-1`)
- **Tenant-based**: `{env}_{tenant}-{service}` (e.g., `<env>_<tenant>-ingestion`)
- **Multi-region**: `{env}-{service}-{region}` (e.g., `staging-rds-us-west-2`)

**Creating workspaces:**

```bash
# Create new workspace
terraform workspace new <env>_<tenant>-ingestion

# Select existing workspace
terraform workspace select <env>_<tenant>-ingestion

# List all workspaces
terraform workspace list

```

### Resource Naming Standard

**Use `this` for main resource:**

```terraform
# ✓ CORRECT - Single main resource

resource "aws_iam_role" "this" {
  name = var.role_name
  ...
}

# ✓ CORRECT - Multiple related resources

resource "aws_iam_role" "app_server" { ... }
resource "aws_iam_role" "worker" { ... }

```

### Validation & Error Handling

**Use validation blocks with meaningful messages:**

```terraform
variable "instance_count" {
  type        = number
  description = "Number of instances to create"

  validation {
    condition     = var.instance_count > 0
    error_message = "Instance count must be greater than 0"
  }
}

```

**Use try() and can() for error handling:**

```terraform
# Safely retrieve optional values
locals {
  vpc_id = try(data.aws_vpc.existing[0].id, "")

  # Check if value can be evaluated
  has_custom_domain = can(var.custom_domain) && var.custom_domain != ""
}

```

### Required Workflow

**ALWAYS follow this sequence:**

```bash
# 1. Format code
terraform fmt -recursive

# 2. Validate syntax
terraform validate

# 3. Run tflint (from repo root)
tflint --config="$(git rev-parse --show-toplevel)/devops/terraform/.tflint.hcl" --recursive

# 4. Plan changes
terraform plan -compact-warnings -out=plan.tfplan -detailed-exitcode -refresh=true

# 5. Review plan output

# 6. Apply (after approval)
terraform apply plan.tfplan

```

**CRITICAL**: NEVER run `terraform apply` without first presenting a plan to the user.

### Module Dependencies

**Common dependency pattern:**

```text
00-core (VPC, Subnets)
  ↓
06-eks (Kubernetes Cluster)
  ↓
deployment/09-<service-name> (Application Services)

```

**Use data sources for cross-module references:**

```terraform
data "terraform_remote_state" "eks" {
  backend = "s3"
  config = {
    bucket = "<org>-terraform-state"
    key    = "eks/<env>-eks-<id>/terraform.tfstate"
    region = "us-east-1"
  }
}

locals {
  cluster_id = data.terraform_remote_state.eks.outputs.cluster_id
}

```

---

## Kubernetes & Helm

### Helm Chart Structure

**Reusable chart pattern:**

```text
helm-reusable-chart/
├── Chart.yaml          # Chart metadata and version
├── values.yaml         # Default values
├── templates/
│   ├── deployment.yaml # Pod deployment
│   ├── service.yaml    # Service definition
│   ├── ingress.yaml    # Ingress rules (optional)
│   ├── serviceaccount.yaml
│   ├── secrets.yaml    # External Secrets Operator
│   └── hpa.yaml        # Horizontal Pod Autoscaler
└── values/
    ├── staging/        # Environment-specific values
    └── production/

```

### Standard Pod Configuration

**Resource Defaults:**

```yaml
resources:
  requests:
    cpu: 250m
    memory: 256Mi
  limits:
    cpu: 500m
    memory: 512Mi

```

**Health Checks (Required):**

```yaml
livenessProbe:
  httpGet:
    path: /health/live
    port: 8080
  initialDelaySeconds: 30
  periodSeconds: 10

readinessProbe:
  httpGet:
    path: /health/ready
    port: 8080
  initialDelaySeconds: 5
  periodSeconds: 5

```

### Service Configuration

**Standard pattern:**

```yaml
service:
  type: ClusterIP
  port: 8080
  targetPort: 8080
  annotations:
    # For Datadog monitoring
    ad.datadoghq.com/tags: '{"env":"production","service":"<app-service>"}'

```

### IAM Roles for Service Accounts (IRSA)

**Service Account with AWS IAM:**

```yaml
serviceAccount:
  create: true
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::<AWS_ACCOUNT_ID>:role/<app-service>-role

```

### External Secrets Operator

**Secret syncing from AWS Secrets Manager:**

```yaml
externalSecrets:
  enabled: true
  secrets:
    - name: database-credentials

      remoteRef:
        key: prod/database/credentials
    - name: api-keys

      remoteRef:
        key: prod/api/keys

```

### Ingress Configuration

**ALB Ingress Pattern:**

```yaml
ingress:
  enabled: true
  className: alb
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/ssl-policy: ELBSecurityPolicy-TLS13-1-2-2021-06
    alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:us-east-1:...
  hosts:
    - host: api.<domain>

      paths:
        - path: /

          pathType: Prefix

```

### Horizontal Pod Autoscaling

**HPA Configuration:**

```yaml
autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 10
  targetCPUUtilizationPercentage: 70
  targetMemoryUtilizationPercentage: 80

```

### Helm Chart Management

**Package and Deploy:**

```bash
# Package chart
helm package helm-reusable-chart/

# Push to registry
helm push <org>-reusable-chart-1.0.0.tgz oci://<AWS_ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/helm

# Install/upgrade with environment values
helm upgrade --install <app-service> \
  oci://<AWS_ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/helm/<org>-reusable-chart \
  --version 1.0.0 \
  --values values/production/<app-service>.yaml \
  --namespace production

```

---

## Container Standards

### Dockerfile Best Practices

**Multi-stage build pattern:**

```dockerfile
# Stage 1: Builder
FROM python:3.12-slim AS builder
WORKDIR /app
COPY poetry.lock pyproject.toml ./
RUN pip install poetry && poetry install --no-dev

# Stage 2: Runtime
FROM python:3.12-slim AS runtime
RUN addgroup --gid 1001 appuser && adduser --uid 1001 --gid 1001 --disabled-password appuser
WORKDIR /app
COPY --from=builder --chown=appuser:appuser /app/.venv ./.venv
COPY --chown=appuser:appuser . .
USER appuser
EXPOSE 8080
CMD ["python", "-m", "uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8080"]

```

**Key Requirements:**

- ✓ Pin base image versions (never use `latest`)
- ✓ Run as non-root user

- ✓ Multi-stage builds for smaller images

- ✓ Use .dockerignore to exclude unnecessary files

- ✓ Clean up package manager caches in same layer

### ECR Repository Management

**Repository defined in `ecr-image-manifest.yaml`:**

```yaml
repositories:
  - name: <service-api>

    image_tag_mutability: MUTABLE
    scan_on_push: true
    lifecycle_policy:
      rules:
        - rulePriority: 1

          description: Keep last 10 images
          selection:
            tagStatus: any
            countType: imageCountMoreThan
            countNumber: 10
          action:
            type: expire

```

**Auto-creation:** Repositories are created automatically by Terraform in the `container.yaml` workflow.

### Image Tagging Strategy

**Use multiple tags:**

```yaml
tags: |
  <AWS_ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/<service-api>:${{ github.sha }}
  <AWS_ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/<service-api>:${{ github.ref_name }}
  <AWS_ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/<service-api>:pr-${{ github.event.number }}
  <AWS_ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/<service-api>:latest

```

### Container Security

**Hadolint validation:**

```bash
# Run hadolint on all Dockerfiles
find . -name "Dockerfile*" -exec hadolint {} \;

```

**Vulnerability scanning:**

- Trivy scan in CI/CD

- ECR scan on push enabled

- Threshold: critical: 1, high: 1, medium: 3

---

## AWS Resources

### Account Structure

- **Production Account**: `<AWS_ACCOUNT_ID>`
- **Development Account**: `<DEV_ACCOUNT_ID>`
- **Region**: `us-east-1` (primary)

### IAM Best Practices

**Least Privilege:**

```terraform
resource "aws_iam_policy" "this" {
  name        = "<app-service>-policy"
  description = "Permissions for <app-service> service"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject"
        ]
        Resource = "arn:aws:s3:::<org>-uploads/*"
      }
    ]
  })
}

```

**OIDC for GitHub Actions:**

```terraform
resource "aws_iam_role" "github_actions" {
  name = "<iam-role-name>"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.github.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          "token.actions.githubusercontent.com:sub" = "repo:<org>/services:ref:refs/heads/main"
        }
      }
    }]
  })
}

```

### Secret Management

**AWS Secrets Manager:**

- Store all sensitive credentials

- Enable automatic rotation

- Use External Secrets Operator to sync to Kubernetes

**Never commit secrets:**

- Use gitleaks scanning (config in `devops/gitleaks.toml`)
- Exemptions in `.gitleaksignore`
- Inject secrets at runtime only

### Tagging Standards

**Required tags for all resources:**

```terraform
tags = {
  Environment = "production"
  Service     = "<app-service>"
  ManagedBy   = "terraform"
  CostCenter  = "engineering"
  Owner       = "platform-team"
}

```

---

## Monitoring & Observability

### Datadog Integration

**Kubernetes monitoring:**

- Datadog agent deployed via Helm

- Service annotations for APM

- Log collection from stdout/stderr

- Custom metrics via DogStatsD

**Terraform modules:**

- `09-datadog-agent/` - Agent deployment

- `09-datadog-monitors/` - Alert configuration

---

## Common Tasks

### Adding a New Service

1. **Create Terraform module** in `devops/terraform/deployment/`
2. **Define ECR repository** in `ecr-image-manifest.yaml`
3. **Create Helm values** in `helm-reusable-chart/values/{env}/`
4. **Add to container workflow** in `.github/workflows/container.yaml`
5. **Add to deployment workflow** in `.github/workflows/{env}_deployments.yaml`

### Updating Kubernetes Deployment

```bash
# 1. Update Helm values file
vim devops/helm-reusable-chart/values/production/<app-service>.yaml

# 2. Apply changes
helm upgrade <app-service> \
  oci://<AWS_ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/helm/<org>-reusable-chart \
  --values devops/helm-reusable-chart/values/production/<app-service>.yaml \
  --namespace production

# 3. Watch rollout
kubectl rollout status deployment/<app-service> -n production

```

### Terraform Module Update

```bash
# 1. Navigate to module
cd devops/terraform/deployment/09-<service-name>

# 2. Select workspace
terraform workspace select <env>_<tenant>-<service-name>

# 3. Format and validate
terraform fmt -recursive
terraform validate

# 4. Plan changes
terraform plan -compact-warnings -out=plan.tfplan -detailed-exitcode -refresh=true

# 5. Review and apply
terraform apply plan.tfplan

```

---

## Troubleshooting

### Terraform State Issues

**State lock errors:**

```bash
# Force unlock (use with caution)
terraform force-unlock <lock-id>

# Check lock in DynamoDB
aws dynamodb scan --table-name terraform-state-lock

```

**Wrong workspace:**

```bash
# List workspaces
terraform workspace list

# Switch to correct workspace
terraform workspace select <env>_<tenant>-service

```

### Kubernetes Debugging

**Pod not starting:**

```bash
# Check pod status
kubectl get pods -n production

# View pod events
kubectl describe pod <pod-name> -n production

# Check logs
kubectl logs <pod-name> -n production --previous

```

**Secret not available:**

```bash
# Check External Secret status
kubectl get externalsecrets -n production
kubectl describe externalsecret <name> -n production

# Verify AWS Secrets Manager
aws secretsmanager get-secret-value --secret-id prod/database/credentials

```

---

## Resources

- [Terraform Style Guide](https://github.com/<org>/<repo>)
- [AWS Well-Architected Framework](https://aws.amazon.com/architecture/well-architected/)
- [Kubernetes Best Practices](https://kubernetes.io/docs/concepts/configuration/overview/)
- [Helm Documentation](https://helm.sh/docs/)

---

**Model**: Claude Sonnet 4.5
**Confidence**: High - Based on existing infrastructure patterns and project-specific configurations
