# CI/CD & Workflow Patterns

## DevOps Principles

### Automation Standards

- Automate all manual tasks—no snowflake environments
- Apply CI/CD pipelines for builds, tests, releases, and infrastructure
- Containerize applications using multi-stage builds
- Store secrets securely and inject them via environment at runtime

### Deployment Strategies

- Use blue-green or canary deployment strategies to minimize risk
- Implement feature flags for controlled rollouts
- Plan rollback procedures for all deployments
- Use infrastructure as code for all environments

### Change Management

- Use Git with consistent branching model (e.g., trunk-based or GitFlow)
- Enforce code reviews and automated checks on pull requests
- Write clear and concise documentation (README, architecture diagrams)
- Embed security checks in every pipeline stage (DevSecOps)

## Language & Build Standards

### Change Detection Patterns

- Detect changes per language/service: python_*, typescript_*, java, go
- Run language-specific linting, testing, and building only on changes
- Use shared common modules as dependencies between services

### Build Matrix Configuration

- Define context, dockerfile, and path_filter for each service
- Map services to container repositories consistently
- Use language-specific base images and build patterns

### Testing Strategy

- Run unit tests per changed module with isolated environments
- Include E2E tests for UI applications (Playwright)
- Use cloud credentials for integration testing in dev environment
- Cache dependencies (Poetry, pnpm, Go modules, Maven) across builds

## Workflow Patterns

### Container Workflow

- Auto-create container repositories via infrastructure during container builds
- Use multi-stage builds with BuildKit caching (type=gha)
- Apply consistent tagging: branch, PR, SHA, semantic versions
- Run Hadolint for Dockerfile linting before builds

### Deployment Workflow

- Use manual dispatch with environment/tenant/application parameters
- Create/select workspaces dynamically based on inputs
- Plan before apply with approval gates for production
- Generate deployment summaries in workflow summary

### Security Integration

- Run vulnerability scans on repository code
- Use secret scanning with custom configuration
- Configure vulnerability thresholds (critical: 1, high: 1, medium: 3)
- Implement GitOps approval workflows for production deployments

## System Design Principles

### Resilience & Scalability

- Design for fault tolerance, observability, and autoscaling
- Apply event-driven design where decoupling is required (e.g., message queues, event buses)
- Minimize blast radius: isolate components via network segments, namespaces, roles
- Protect systems with defense-in-depth: TLS, authentication, firewalls, WAF, MFA

### Performance & Monitoring

- Design systems for horizontal scaling
- Implement comprehensive observability (logs, metrics, traces)
- Use caching strategies appropriately
- Plan for graceful degradation under load

## Quality Assurance

### Pipeline Standards

- Every pipeline must include linting and testing stages
- Use proper artifact management and versioning
- Implement proper logging and monitoring of pipeline execution
- Include proper error handling and notification systems

### Environment Management

- Use consistent environment promotion patterns
- Implement proper configuration management across environments
- Use infrastructure as code for environment provisioning
- Maintain environment parity where possible
