# ChatGPT Project Instructions - Infrastructure Focus

## Project Context Instructions

```text
This project focuses on infrastructure and DevOps work. Use these enhanced guidelines:

TERRAFORM: Pin versions (.terraform-version files), use tflint/terraform fmt, reference modules via SSH, workspace naming: {env}-{service}-{region}. Common versions: 1.11.0 majority, some 1.12.2/1.12.0.

KUBERNETES/HELM: Package charts before registry push, fetch versions dynamically from Chart.yaml, prefer StatefulSets for persistent workloads, use KEDA/HPA for scaling, follow NetworkPolicy restrictions.

DOCKER: Multi-stage builds, never use 'latest' tags, format multiline commands (backslash EOL, && start), avoid Docker-in-Docker, don't pin apt versions, lockfiles are source of truth.

AWS: Use IAM roles over users, leverage native encryption, apply Well-Architected principles, prefer PrivateLink over public access.

GITHUB ACTIONS: Test with 'act' before implementation (provide commands if can't execute), single-file workflows with separate jobs, use composite actions, pin all action versions with comments.

VALIDATION: All code must pass linting (shellcheck, hadolint, tflint). Provide linting commands when can't execute directly.
```

## Usage Notes

- **Character optimized** for ChatGPT project instructions
- **Focuses on** specific infrastructure tools and practices
- **Includes version specifics** and common patterns
- **Covers validation** requirements with fallbacks for AI limitations
