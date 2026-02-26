# Kubernetes & Helm Standards

## Kubernetes Best Practices

- Use Helm charts for managing application deployments
- Follow GitOps principles to manage cluster state declaratively
- Use workload identities (e.g., IRSA on AWS) for secure pod access to cloud resources
- Prefer StatefulSets for persistent workloads with identity needs
- Apply Horizontal Pod Autoscaler (HPA) or KEDA for event-based autoscaling
- Define and enforce NetworkPolicy for inter-service traffic restrictions
- Use resource limits and requests to ensure fair scheduling
- Avoid running privileged containers; follow PodSecurity standards

## Helm Chart Structure

- Use single reusable chart with tenant-specific values overrides
- Organize values by environment and service
- Support multi-tenancy with service-specific configurations
- Use consistent templating patterns across charts

## Service Configuration

### Resource Defaults

- Default resources: 250m CPU / 256Mi memory requests, 500m CPU / 512Mi memory limits
- Use ClusterIP services with port 8080 default
- Enable probes with /health endpoint by default
- Use appropriate storage class for persistent volumes (e.g., gp3 for AWS)

### Security Patterns

- Create service accounts with cloud IAM role annotations
- Use External Secrets Operator for secret management
- Follow cloud-specific role naming conventions
- Enable logging annotations for observability

## Scaling Configuration

### Autoscaling Options

- Choose between KEDA (event-driven) or HPA (metrics-based) scaling
- Default HPA: 1-1 replicas, 80% CPU utilization threshold
- Configure Pod Disruption Budgets for production services
- Consider vertical pod autoscaling for appropriate workloads

### Multi-Tenancy Patterns

#### Configuration Separation

- Use tenant-specific Helm values files for service configuration
- Configure tenant-specific queues, databases, and storage paths
- Apply tenant-specific IAM roles and security policies
- Use environment variables for tenant-specific resource naming

#### Resource Scaling

- Configure tenant-specific resource requests/limits based on usage
- Use tenant-specific database connections and schemas
- Apply tenant-specific monitoring and logging configurations
- Scale replicas based on tenant workload requirements

#### Deployment Isolation

- Use Kubernetes namespaces for tenant separation
- Deploy tenant-specific service instances with isolated resources
- Configure tenant-specific ingress rules and external endpoints
- Maintain tenant-specific backup and disaster recovery procedures

#### Security Boundaries

- Implement network policies for tenant traffic isolation
- Use separate service accounts per tenant where applicable
- Apply tenant-specific encryption keys and secrets
- Audit tenant access patterns and resource usage

## Development Practices

### Chart Development

- When using Helm, prefer editing `values.yaml` directly
- Use consistent templating and naming conventions
- Include proper documentation for all values
- Test charts in multiple environments before deployment

### Chart Management

- After making changes to the Helm chart, it must be packaged and pushed to the container registry before attempting to install or upgrade using the chart from registry
- In CI/CD workflows, the Helm chart version should be fetched dynamically from Chart.yaml instead of hardcoding the version
- Use single source of truth for Helm chart versions, ideally defined in the chart YAML

### Configuration Management

- Use environment-specific values files
- Apply proper secret management practices
- Include health checks and monitoring configuration
- Document all configuration options and their purposes
