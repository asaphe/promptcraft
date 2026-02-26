# Terraform Standards

## Structure & Organization

- Use numbered prefixes for infrastructure layers (00-core, 01-network, 02-dns, etc.)
- Maintain clear separation between foundational (00-05) and application-specific (99-) infrastructure
- Use template directory for standardized module scaffolding
- Always include backend.tf, providers.tf, variables.tf, and versions.tf in each module

## State Management

- Use S3 backend with appropriate bucket naming convention
- Enable encryption and use DynamoDB for state locking
- Use Terraform workspaces for environment and service separation
- Follow workspace naming: "{env}-{service}-{region}" or "{env}_{tenant}-{service}"

## Code Quality

- Run "terraform fmt -recursive" before commits
- Use tflint with central config (.tflint.hcl) for code quality
- Pin Terraform version using .terraform-version file
- Reference external modules via SSH with depth parameter for performance
- Use environment-specific .tfvars files (dev.tfvars, prod.tfvars, root.tfvars)

## Module Development

- Use Terraform modules for repeatable infrastructure patterns
- Keep modules small, focused, and composable
- Name resources with consistent convention: env-resource-purpose
- Use locals, variables, and outputs effectively to simplify logic and reuse
- Separate environments using workspaces or directory structure

## Security & Best Practices

- Always pin provider versions and module sources
- Use terraform fmt, tflint, and-or checkov for linting and security
- Avoid data races: reference outputs or data sources, never implicitly rely on apply order
- Use terraform plan and version control before apply
- Manage secrets with remote backends (e.g., AWS S3 + DynamoDB + KMS)

## Variables & Configuration

- Always include aws_region, aws_profile, and cidr_blocks variables where applicable
- Use consistent versioning and configuration patterns
- Document all variables with descriptions and types
- Use validation rules where appropriate
- Provide sensible defaults while allowing customization

## Version Management

- Projects may have extensive .terraform-version files throughout modules using different versions
- Respect existing version pinning in .terraform-version files
- Common versions in use: majority 1.11.0, some 1.12.2, some 1.12.0
- Use Terraform to deploy operators like KEDA operator Helm chart when appropriate

## Development Workflow

- Before providing any Terraform code, test it to confirm it works as expected
- When modifying variables, validation, or logic:
  - Explain why the change is necessary
  - Provide Terraform documentation links to back up claims
  - Compare new version with old version and describe improvements
- If an error occurs, before suggesting a fix:
  - Analyze the exact Terraform error message and explain what is happening
  - Reference official Terraform documentation
  - Ensure the solution directly addresses the cause of the error
  - Confirm that Terraform will not crash or fail due to unexpected behavior
