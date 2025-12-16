# Claude Code Documentation Templates

This directory contains production-tested templates for organizing Claude Code documentation in your repositories.

## Directory Structure

```text
claude/
├── project-templates/          # Ready-to-use documentation templates
│   ├── navigation-hub.md             # Central navigation/overview
│   ├── codebase-guide-template.md    # Development workflows & architecture
│   ├── github-actions-guide.md       # GitHub Actions best practices
│   └── devops-infrastructure-guide.md # Terraform, K8s, infrastructure
├── specs/                      # Detailed specifications
│   └── ci-cd-specification.md        # RFC-style CI/CD standards
└── README.md                   # This file

Note: Cursor IDE rules are in ../cursor/mdc-rules/ (existing structure)
```

## Templates Overview

### Project Templates (`project-templates/`)

Ready-to-customize documentation templates for your repository:

#### navigation-hub.md

**Purpose:** Central navigation and overview for `.claude/CLAUDE.md`

**Features:**

- Documentation organization and links
- Quick start guides for different roles
- Technology stack overview
- Architecture patterns summary
- Key principles and standards

**Use When:** Setting up `.claude/` directory structure

**Customization Needed:**

- Replace placeholder text with your project specifics
- Update file paths to match your structure
- Add/remove sections based on your needs

#### codebase-guide-template.md

**Purpose:** Comprehensive development guide

**Features:**

- Essential commands (build, test, run)
- Architecture overview and patterns
- Local development setup
- Common workflows
- Integration points
- Troubleshooting guides

**Use When:** Onboarding new developers, documenting architecture

**Customization Needed:**

- Replace `<service-name>`, `<module>` with actual names
- Update commands with project-specific syntax
- Document your actual architecture patterns
- Add project-specific workflows

#### github-actions-guide.md

**Purpose:** GitHub Actions workflow development standards

**Features:**

- Mandatory testing protocols (act testing, path validation)
- Project-specific patterns
- Change detection strategies
- Container build workflows
- Deployment patterns
- Security integration

**Use When:** Creating `.github/CLAUDE.md` for workflow guidance

**Customization Needed:**

- Replace `<AWS_ACCOUNT_ID>`, `<ECR_REGISTRY>` with your values
- Update service names and paths
- Customize matrix configurations
- Add project-specific workflows

#### devops-infrastructure-guide.md

**Purpose:** Infrastructure and Kubernetes documentation

**Features:**

- Terraform module organization
- Backend configuration patterns
- Workspace naming conventions
- Kubernetes & Helm standards
- Container best practices
- AWS/Cloud provider patterns
- Monitoring and troubleshooting

**Use When:** Creating `devops/CLAUDE.md` for infrastructure work

**Customization Needed:**

- Replace `<AWS_ACCOUNT_ID>`, `<org>`, `<domain>` with actual values
- Update Terraform module structure
- Customize Helm chart patterns
- Document your cloud resources

### Specifications (`specs/`)

#### ci-cd-specification.md

**Purpose:** RFC-style specification for CI/CD standards

**Features:**

- Iron rules (act testing, path validation, naming)
- GitHub Actions standards
- Terraform standards
- Docker standards
- Validation protocols
- Multi-language standards

**Use When:** Establishing team-wide CI/CD standards

**Customization:** Minimal - already generic and comprehensive

**Note:** Cursor IDE rules are maintained separately in `../cursor/mdc-rules/` directory. A Kubernetes/Helm rule has been added there.

## Usage Guide

### Setting Up a New Repository

1. **Create `.claude/` directory structure:**

   ```bash
   mkdir -p .claude/specs
   ```

2. **Copy navigation hub:**

   ```bash
   cp claude/project-templates/navigation-hub.md .claude/CLAUDE.md
   ```

3. **Copy codebase guide:**

   ```bash
   cp claude/project-templates/codebase-guide-template.md .claude/CODEBASE.md
   ```

4. **Copy CI/CD spec:**

   ```bash
   cp claude/specs/ci-cd-specification.md .claude/specs/
   ```

5. **Customize the files:**
   - Replace all `<placeholder>` values
   - Update service names, paths, and commands
   - Add project-specific sections

6. **Add directory-specific guides:**

   ```bash
   cp claude/project-templates/github-actions-guide.md .github/CLAUDE.md
   cp claude/project-templates/devops-infrastructure-guide.md devops/CLAUDE.md
   ```

7. **Set up selective git tracking:**

   ```bash
   # Create .claude/.gitignore
   echo "settings.local.json" > .claude/.gitignore
   echo "*.local.*" >> .claude/.gitignore

   # Update root .gitignore
   # Remove: .claude/
   # Add: .claude/settings.local.json
   #      .claude/*.local.*
   ```

**Note:** For Cursor IDE rules, see the existing `cursor/` directory structure with mdc-rules templates.

## Placeholder Reference

Common placeholders used in templates:

### Company/Organization

- `<COMPANY>` - Company name
- `<org>` - Organization name (lowercase)
- `<organization>` - Organization name (in URLs)
- `<repo-name>` - Repository name
- `<domain>` - Domain name (e.g., company.com)

### Cloud/Infrastructure

- `<AWS_ACCOUNT_ID>` - AWS account ID
- `<DEV_ACCOUNT_ID>` - Development account ID
- `<ECR_REGISTRY>` - ECR registry URL
- `<env>` - Environment (dev, staging, prod)
- `<tenant>` - Tenant identifier

### Services/Applications

- `<service-name>` - Generic service name
- `<service-api>` - API service name
- `<app-service>` - Application service
- `<module>` - Python module name
- `<app>` - TypeScript app name

### Databases/Queues

- `<app_db>` - Application database
- `<domain_db>` - Domain-specific database
- `<workflow_db>` - Workflow engine database
- `<insight-queue>` - Insight notification queue
- `<mesh-requests-queue>` - Agent mesh queue

### IAM/Security

- `<iam-role-name>` - IAM role name
- `<state-access-role>` - Terraform state access role
- `<bucket-name>` - S3 bucket name

## Best Practices

1. **Start with navigation hub** - Use `navigation-hub.md` as your `.claude/CLAUDE.md`
2. **Progressive disclosure** - Link to detailed guides from the hub
3. **Directory-specific guides** - Place guides close to the code they document
4. **Version control** - Commit all `.claude/` docs except `settings.local.json`
5. **Regular updates** - Review quarterly or when patterns change
6. **Team collaboration** - Submit PRs for documentation improvements

## Based On

These templates are extracted from a production monorepo with:

- 40+ microservices across Python, TypeScript, Java, and Go
- Event-driven architecture with AWS SQS
- Kubernetes deployment via Helm charts
- Terraform infrastructure (~40 modules)
- Comprehensive CI/CD via GitHub Actions

All company-specific and personally identifiable information has been sanitized.

## Contributing

Improvements welcome! If you find issues or have suggestions:

1. Test changes in a real project first
2. Ensure all placeholders are clearly marked
3. Keep templates generic and reusable
4. Update this README with any new patterns

---

**Last Updated**: 2025-12-16
**Template Version**: 1.0
