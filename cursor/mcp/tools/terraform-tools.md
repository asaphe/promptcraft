# Terraform MCP Tools

## Overview

The Terraform MCP server enables AI assistants to interact with Terraform configurations, HCP Terraform, and provide intelligent infrastructure guidance.

## Features

### Terraform Module Registry Access

- Search for modules across public and private registries
- Get module documentation and usage examples
- Validate module compatibility and versions

### HCP Terraform Integration

- Access workspace information
- Review run history and status
- Get policy and sentinel data

### Configuration Analysis

- Parse and understand Terraform configurations
- Suggest improvements and best practices
- Identify potential security issues

### Documentation Generation

- Generate README files for modules
- Create usage examples
- Document variable descriptions and outputs

## Installation

### Option 1: Go Installation (Recommended)

```bash
# Install Go if not already installed
brew install go  # macOS
# or download from https://golang.org/dl/

# Install terraform-mcp-server
go install github.com/hashicorp/terraform-mcp-server@latest

# Verify installation
~/go/bin/terraform-mcp-server --version
```

### Option 2: Binary Download

```bash
# Download latest release from GitHub
curl -L -o terraform-mcp-server https://github.com/hashicorp/terraform-mcp-server/releases/latest/download/terraform-mcp-server-$(uname -s)-$(uname -m)

# Make executable
chmod +x terraform-mcp-server

# Move to PATH
sudo mv terraform-mcp-server /usr/local/bin/
```

## Configuration

### Basic Configuration

```json
{
  "mcpServers": {
    "hcp-terraform": {
      "command": "/path/to/terraform-mcp-server",
      "args": ["stdio"]
    }
  }
}
```

### Advanced Configuration with Environment Variables

```json
{
  "mcpServers": {
    "hcp-terraform": {
      "command": "/path/to/terraform-mcp-server",
      "args": ["stdio"],
      "env": {
        "TF_CLOUD_TOKEN": "op://YourVault/HCP-Terraform-Token/password",
        "TF_REGISTRY_TOKEN": "op://YourVault/Registry-Token-Name/password"
      }
    }
  }
}
```

## Authentication

### HCP Terraform Token

1. **Create API Token**:
   - Go to HCP Terraform → User Settings → Tokens
   - Create new token with appropriate permissions

2. **Store in 1Password**:

   ```bash
   op item create \
     --category="API Credential" \
     --title="HCP Terraform Token" \
     --vault="Private" \
     password="your-token-here"
   ```

### Terraform Registry Token (if needed)

For private module registries:

1. **Generate registry token** from your private registry
2. **Store securely** in 1Password or environment variables

## Usage Examples

### Module Discovery

**Ask AI**: "Find Terraform modules for AWS VPC with specific CIDR requirements"

**AI can**:

- Search public and private registries
- Compare module features
- Provide usage examples
- Check compatibility with your Terraform version

### Configuration Review

**Ask AI**: "Review my Terraform configuration for security best practices"

**AI can**:

- Analyze resource configurations
- Identify security vulnerabilities
- Suggest improvements
- Check for deprecated resources

### Module Documentation

**Ask AI**: "Generate documentation for my Terraform module"

**AI can**:

- Create comprehensive README
- Document all variables and outputs
- Provide usage examples
- Generate module dependency graphs

### Error Debugging

**Ask AI**: "Help debug this Terraform plan error"

**AI can**:

- Analyze error messages
- Suggest configuration fixes
- Provide alternative approaches
- Reference official documentation

## Best Practices

### Security

- **Use least-privilege tokens** for HCP Terraform access
- **Store all credentials** in 1Password or similar secure storage
- **Rotate tokens regularly** following security policies
- **Audit token usage** through HCP Terraform logs

### Performance

- **Cache module information** when possible
- **Limit concurrent requests** to avoid rate limiting
- **Use specific module versions** rather than latest

### Integration

- **Combine with filesystem MCP** for local Terraform file access
- **Use with GitHub MCP** for repository-based workflows
- **Integrate with documentation** generation workflows

## Troubleshooting

### Common Issues

**Server won't start**:

```bash
# Check Go installation
go version

# Verify server binary
ls -la ~/go/bin/terraform-mcp-server

# Test server directly
~/go/bin/terraform-mcp-server --help
```

**Authentication failures**:

```bash
# Test HCP Terraform connection
curl -H "Authorization: Bearer $TF_CLOUD_TOKEN" \
     https://app.terraform.io/api/v2/account/details

# Verify 1Password CLI
op item get "HCP Terraform Token"
```

**Registry access issues**:

- Verify token permissions
- Check network connectivity
- Ensure registry URLs are correct

### Debug Mode

Enable verbose logging:

```json
{
  "mcpServers": {
    "hcp-terraform": {
      "command": "/path/to/terraform-mcp-server",
      "args": ["stdio", "--log-level", "debug"],
      "env": {
        "TF_LOG": "DEBUG"
      }
    }
  }
}
```

## Advanced Features

### Custom Registry Configuration

```json
{
  "env": {
    "TF_REGISTRY_HOST": "registry.company.com",
    "TF_REGISTRY_TOKEN": "op://YourVault/Company-Registry-Token/password"
  }
}
```

### Workspace-Specific Settings

```json
{
  "env": {
    "TF_WORKSPACE": "production",
    "TF_ORGANIZATION": "your-org-name"
  }
}
```

This setup provides comprehensive Terraform integration for infrastructure-as-code workflows with AI assistance!
