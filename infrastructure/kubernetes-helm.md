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

## Node Autoscaler Alignment (Karpenter / Cluster Autoscaler)

### Capacity-Type Consistency

When using node autoscalers that provision nodes based on pod requirements:

- **Verify nodeSelector and node pool alignment** — If a pod uses `nodeSelector` to request a specific capacity type (e.g., `spot` or `on-demand`), verify the target node pool actually offers that capacity type. A mismatch means pods will never schedule, resulting in silent job timeouts.
- **Always include on-demand fallback for time-sensitive workloads** — Job runners, batch processors, and CI pods should have `["spot", "on-demand"]` capacity types in their node pool. Spot-only pools risk scheduling failures when spot capacity is unavailable.
- **Use standard instance families as defaults** — Never default to exotic or specialized instance families (storage-optimized, GPU, etc.) in node pool configurations. These have limited spot availability and may have zero capacity in some availability zones. Default to general-purpose or compute-optimized families. Override to specialized families only when the workload explicitly requires them.

### Multi-Taint Node Pools

When a node pool uses multiple taints for workload isolation:

- **Document which pods tolerate which taints** — If a node pool has both a namespace taint and a workload-type taint (e.g., `my-namespace:NoSchedule` + `batch-jobs:NoSchedule`), only pods with both tolerations can schedule there. Infrastructure pods (daemons, webservers) typically only get the namespace toleration and land on general-purpose pools.
- **Verify tolerations match the full taint set** — A pod targeting a multi-taint node pool must tolerate ALL taints. Missing even one toleration means the pod cannot schedule on that pool, even if the nodeSelector matches.

### Incident Response: kubectl Over IaC

During active scheduling incidents:

- **Use kubectl/helm patches for immediate fixes** — IaC tools (Terraform `helm_release`, etc.) can have long timeouts (10-15 minutes). For urgent fixes, patch deployments or node pools directly via `kubectl patch` or `helm upgrade`. The IaC state converges after the PR merges.
- **Draw conclusions from early signals** — Check pod events and scheduling status within seconds of a change. Don't wait for full IaC apply completion to verify a fix works. Karpenter events, `FailedScheduling` messages, and `NodeClaim` creation are immediate signals.

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
