# AWS Guidelines

## Access Control

- Prefer IAM roles over users for programmatic access
- Use specific resources in IAM policies when applicable (check AWS documentation for resource-level permissions)
- Use Service Control Policies (SCPs) and IAM policies to enforce guardrails
- Enable and enforce CloudTrail, Config Rules, and GuardDuty
- Use OIDC for GitHub Actions AWS authentication
- Implement least-privilege IAM policies for service roles
- Use workload identity patterns for pod-to-AWS service communication

## Security & Operations

- Tag all resources consistently (Environment, Owner, CostCenter)
- Use Auto Scaling Groups and Load Balancers for high availability
- Leverage native encryption (S3 SSE, RDS encryption, KMS)
- Avoid public access to services unless explicitly needed (use PrivateLink)
- Follow Well-Architected Framework pillars: Security, Reliability, Performance, Cost, and Operational Excellence

## Secret Management

- Use AWS Secrets Manager for database credentials and API keys
- Never hardcode secrets in configuration files or containers
- Use External Secrets Operator to sync secrets into Kubernetes
- Rotate secrets regularly and use automated secret injection
- Mask sensitive values in CI/CD logs and outputs

## Network Security

- Use VPC endpoints where possible to avoid internet traffic
- Implement proper security groups with minimal required access
- Use NACLs for additional network-level security
- Enable VPC Flow Logs for network monitoring
- Use AWS WAF for web application protection

## Cost Optimization

- Use appropriate instance types for workloads
- Implement auto-scaling to match demand
- Use Reserved Instances or Savings Plans for predictable workloads
- Monitor and optimize unused resources
- Use lifecycle policies for S3 storage optimization

## Monitoring & Observability

- Enable CloudWatch monitoring for all services
- Set up appropriate alarms and notifications
- Use X-Ray for application tracing
- Implement centralized logging strategies
- Monitor costs and usage patterns

## Compliance & Governance

- Enable AWS Config for compliance monitoring
- Use AWS Organizations for account management
- Implement proper backup and disaster recovery procedures
- Regular security assessments and penetration testing
- Document all architectural decisions and changes
