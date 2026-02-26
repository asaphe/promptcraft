# 1Password CLI Integration for MCP

## Overview

1Password CLI integration provides secure credential management for MCP servers, eliminating the need to store sensitive tokens and API keys in configuration files or environment variables.

## Benefits

### Security Advantages

- **No hardcoded secrets** in configuration files
- **Centralized credential management** with 1Password vaults
- **Automatic token rotation** support
- **Audit trail** for credential access
- **Multi-device synchronization** of credentials

### Operational Benefits

- **Easy credential sharing** across team members
- **Environment-specific vaults** (development, staging, production)
- **Consistent credential naming** and organization
- **Backup and recovery** of all credentials

## Installation & Setup

### 1. Install 1Password CLI

#### macOS

```bash
# Using Homebrew (recommended)
brew install --cask 1password/tap/1password-cli

# Or download directly from:
# https://app-updates.agilebits.com/product_history/CLI2
```

#### Linux

```bash
# Download and install
curl -sS https://downloads.1password.com/linux/keys/1password.asc | \
  sudo gpg --dearmor --output /usr/share/keyrings/1password-archive-keyring.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/1password-archive-keyring.gpg] https://downloads.1password.com/linux/debian/$(dpkg --print-architecture) stable main" | \
  sudo tee /etc/apt/sources.list.d/1password.list

sudo apt update && sudo apt install 1password-cli
```

#### Windows

```powershell
# Using winget
winget install 1Password.CLI

# Or download from 1Password website
```

### 2. Sign In to 1Password

```bash
# Sign in to your 1Password account
op account add --address your-team.1password.com --email your-email@company.com

# Or for individual accounts
op account add --address my.1password.com --email your-email@gmail.com

# Sign in
op signin

# Verify authentication
op account list
```

### 3. Configure Biometric Unlock (Recommended)

```bash
# Enable biometric unlock for seamless access
op biometric enable

# Test biometric unlock
op item list --vault Private
```

## Credential Organization

### Vault Structure

#### Personal Development

```text
PersonalVault/                   # Personal development credentials
├── GitHub-Token-Name            # GitHub personal access token
├── HCP-Terraform-Token          # HCP Terraform access token
├── AWS-Dev-Credentials          # AWS development credentials
└── NPM-Registry-Token           # NPM registry token
```

#### Work/Enterprise

```text
WorkVault/                 # Work-related credentials
├── GitHub-Work-Token      # Work GitHub access token
├── Company-Registry-Token # Company private registry
├── AWS-Prod-Credentials   # Production AWS credentials
└── K8s-Cluster-Tokens     # Kubernetes cluster tokens

DevVault/                  # Development environment
├── Dev-Database-Creds     # Development database
├── Staging-API-Keys       # Staging environment APIs
└── Test-Service-Tokens    # Testing service tokens
```

### Item Naming Conventions

Use consistent naming patterns:

- **Service-Environment-Purpose**: `GitHub-Prod-MCP-Token`
- **Tool-Context-Type**: `Terraform-HCP-API-Token`
- **Project-Service-Credential**: `ProjectX-Database-Password`

## Creating Credentials

### GitHub Token Example

```bash
# Create GitHub MCP token item
op item create \
  --category="API Credential" \
  --title="GitHub-Token-Name" \
  --vault="YourVault" \
  --url="https://github.com/settings/tokens" \
  --tags="mcp,github,development" \
  username="your-github-username" \
  password="ghp_your_token_here" \
  --notes="Personal access token for GitHub MCP server - expires 2024-12-31"

# Add custom fields
op item edit "GitHub-Token-Name" \
  --vault="YourVault" \
  scopes="repo,read:org,read:user" \
  created="2024-01-15" \
  expires="2024-12-31"
```

### Terraform Token Example

```bash
# Create HCP Terraform token
op item create \
  --category="API Credential" \
  --title="HCP-Terraform-Token" \
  --vault="YourVault" \
  --url="https://app.terraform.io/app/settings/tokens" \
  --tags="mcp,terraform,hcp" \
  password="your-terraform-token-here" \
  --notes="HCP Terraform API token for MCP server access"
```

### Database Credentials Example

```bash
# Create database credentials
op item create \
  --category="Database" \
  --title="Project-Dev-Database" \
  --vault="DevVault" \
  --url="postgres://localhost:5432/project_dev" \
  username="project_user" \
  password="secure_password_here" \
  database="project_dev" \
  hostname="localhost" \
  port="5432"
```

## MCP Configuration Patterns

### Basic 1Password Integration

```json
{
  "mcpServers": {
    "github": {
      "command": "op",
      "args": [
        "run",
        "--",
        "npx",
        "-y",
        "@modelcontextprotocol/server-github"
      ],
      "env": {
        "GITHUB_TOKEN": "op://YourVault/GitHub-Token-Name/password"
      }
    }
  }
}
```

### Multiple Credentials

```json
{
  "mcpServers": {
    "terraform": {
      "command": "op",
      "args": [
        "run",
        "--",
        "/path/to/terraform-mcp-server",
        "stdio"
      ],
      "env": {
        "TF_CLOUD_TOKEN": "op://YourVault/HCP-Terraform-Token/password",
        "AWS_ACCESS_KEY_ID": "op://WorkVault/AWS-Credentials-Name/username",
        "AWS_SECRET_ACCESS_KEY": "op://WorkVault/AWS-Credentials-Name/password"
      }
    }
  }
}
```

### Environment-Specific Vaults

```json
{
  "mcpServers": {
    "github-development": {
      "command": "op",
      "args": ["run", "--", "npx", "-y", "@modelcontextprotocol/server-github"],
      "env": {
        "GITHUB_TOKEN": "op://DevVault/GitHub-Dev-Token/password"
      }
    },
    "github-production": {
      "command": "op",
      "args": ["run", "--", "npx", "-y", "@modelcontextprotocol/server-github"],
      "env": {
        "GITHUB_TOKEN": "op://ProdVault/GitHub-Prod-Token/password"
      }
    }
  }
}
```

## Security Best Practices

### Vault Organization

1. **Separate vaults by environment**: Development, Staging, Production
2. **Use appropriate sharing**: Team vaults for shared credentials
3. **Regular vault audits**: Review access and unused credentials
4. **Descriptive tags**: Tag items by service, environment, purpose

### Token Management

1. **Minimum required scopes**: Only grant necessary permissions
2. **Regular rotation**: Set expiration dates and rotate tokens
3. **Document purposes**: Clear notes about token usage
4. **Monitor usage**: Track token access through service logs

### Access Control

1. **Principle of least privilege**: Only access required vaults
2. **Two-factor authentication**: Enable 2FA for 1Password account
3. **Biometric unlock**: Use Touch ID/Face ID when available
4. **Session management**: Configure appropriate session timeouts

## Advanced Configurations

### Dynamic Credential Selection

```json
{
  "mcpServers": {
    "github-dynamic": {
      "command": "op",
      "args": [
        "run",
        "--",
        "sh",
        "-c",
        "GITHUB_TOKEN=$(op item get GitHub-${ENVIRONMENT:-dev}-Token --fields password) npx -y @modelcontextprotocol/server-github"
      ]
    }
  }
}
```

### Custom Field Access

```json
{
  "env": {
    "GITHUB_TOKEN": "op://YourVault/GitHub-Token-Name/password",
    "GITHUB_USERNAME": "op://YourVault/GitHub-Token-Name/username",
    "GITHUB_API_URL": "op://YourVault/GitHub-Token-Name/api_url",
    "TOKEN_EXPIRES": "op://YourVault/GitHub-Token-Name/expires"
  }
}
```

### Conditional Credential Loading

```bash
#!/bin/bash
# Script: load-mcp-credentials.sh

if op item get "GitHub-Token-Name" --vault YourVault >/dev/null 2>&1; then
  export GITHUB_TOKEN=$(op item get "GitHub-Token-Name" --vault YourVault --fields password)
else
  echo "Warning: GitHub MCP token not found"
  exit 1
fi

# Continue with MCP server startup
npx -y @modelcontextprotocol/server-github
```

## Troubleshooting

### Common Issues

**Authentication failures**:

```bash
# Check 1Password CLI authentication
op account list

# Re-authenticate if needed
op signin

# Test credential access
op item get "GitHub-Token-Name" --fields password
```

**Permission errors**:

```bash
# Check vault access
op vault list

# Verify item exists
op item list --vault YourVault | grep GitHub

# Check item permissions
op item get "GitHub-Token-Name" --vault YourVault
```

**Script execution issues**:

```bash
# Verify op command is in PATH
which op

# Test 1Password CLI
op --version

# Debug credential retrieval
op run --dry-run -- echo "GITHUB_TOKEN is \$GITHUB_TOKEN"
```

### Debug Mode

Enable verbose 1Password CLI logging:

```json
{
  "mcpServers": {
    "github-debug": {
      "command": "op",
      "args": [
        "run",
        "--debug",
        "--",
        "npx",
        "-y",
        "@modelcontextprotocol/server-github"
      ],
      "env": {
        "GITHUB_TOKEN": "op://YourVault/GitHub-Token-Name/password",
        "OP_DEBUG": "true"
      }
    }
  }
}
```

## Team Collaboration

### Shared Vault Setup

```bash
# Create team vault for shared MCP credentials
op vault create "Team-MCP-Credentials" --description "Shared MCP server credentials for development team"

# Add team members
op user confirm --vault "Team-MCP-Credentials" teammate@company.com

# Share common credentials
op item move "GitHub-Team-Token" --from Private --to "Team-MCP-Credentials"
```

### Standardized Credential Names

Create team standards for credential naming:

```text
Team-MCP-Credentials/
├── GitHub-Team-Token          # Shared GitHub access
├── HCP-Terraform-Team-Token   # Shared Terraform access
├── AWS-Dev-Shared-Creds       # Development AWS access
└── K8s-Dev-Cluster-Token      # Development Kubernetes access
```

This 1Password integration provides enterprise-grade security for MCP credential management while maintaining ease of use and team collaboration!
