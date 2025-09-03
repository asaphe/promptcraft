# Cursor MCP Setup Guide

## Installation Steps

### 1. Install Prerequisites

```bash
# Install Node.js (if not already installed)
# Visit: https://nodejs.org/

# Install 1Password CLI
brew install --cask 1password/tap/1password-cli

# Install Go (for terraform-mcp-server)
brew install go

# Install terraform-mcp-server
go install github.com/hashicorp/terraform-mcp-server@latest
```

### 2. Configure MCP in Cursor

1. **Open Cursor Settings**
   - Press `Cmd+,` (macOS) or `Ctrl+,` (Windows/Linux)
   - Go to "Features" → "Model Context Protocol"

2. **Add Configuration**
   - Copy the content from `configuration.json`
   - Paste into the MCP configuration field

### 3. Customize Configuration

#### Update File Paths

Replace placeholder paths with your actual directories:

```json
"filesystem": {
  "command": "npx",
  "args": [
    "-y",
    "fast-filesystem-mcp",
    "/Users/yourusername/projects",        // Your main projects directory
    "/Users/yourusername/workspace",       // Your workspace directory
    "/Users/yourusername/Downloads",       // Downloads folder (if needed)
    "/Users/yourusername/Documents"        // Documents folder (if needed)
  ]
}
```

#### Update Terraform Server Path

Find your Go binary path:

```bash
go env GOPATH
# Usually: /Users/yourusername/go

# Update configuration:
# "/path/to/terraform-mcp-server" → "/Users/yourusername/go/bin/terraform-mcp-server"
```

### 4. Set Up GitHub Integration

#### Create GitHub Token

1. Go to GitHub Settings → Developer settings → Personal access tokens → Tokens (classic)
2. Generate new token with scopes:
   - `repo` (full repository access)
   - `read:org` (read organization data)
   - `read:user` (read user profile data)

#### Store in 1Password

1. Create new item in 1Password:
   - **Title**: "GitHub MCP Token"
   - **Type**: "Password" or "API Credential"
   - **Password field**: Your GitHub token
   - **Vault**: Choose appropriate vault (update config if not "Private")

2. Update configuration reference if needed:

   ```json
   "env": {
     "GITHUB_TOKEN": "op://YourVault/GitHub-Token-Name/password"
   }
   ```

### 5. Test Configuration

1. **Restart Cursor** after configuration changes
2. **Test filesystem access**:
   - Open a new chat
   - Ask: "List files in my projects directory"
3. **Test GitHub integration**:
   - Ask: "Show my recent GitHub repositories"
4. **Test Terraform integration**:
   - Ask: "Help me with Terraform module syntax"

## Security Best Practices

### Filesystem Access

- **Limit directories** to only what you need
- **Avoid system directories** (/, /System, /usr, etc.)
- **Use specific project paths** rather than entire home directory

### Credential Management

- **Never hardcode tokens** in configuration
- **Use 1Password CLI** for all sensitive credentials
- **Rotate tokens regularly**
- **Use minimum required scopes** for GitHub tokens

### Network Security

- **Review MCP server permissions** before installation
- **Use official servers** when possible
- **Keep servers updated** to latest versions

## Troubleshooting

### Common Issues

**MCP servers not loading:**

- Check that all prerequisites are installed
- Verify file paths are correct
- Restart Cursor after configuration changes

**1Password authentication fails:**

- Ensure 1Password CLI is signed in: `op account list`
- Check vault and item names match configuration
- Verify item has correct field name ("password")

**Terraform server issues:**

- Confirm Go installation: `go version`
- Check terraform-mcp-server path: `which terraform-mcp-server`
- Ensure server is executable

**Filesystem access denied:**

- Verify directory paths exist
- Check directory permissions
- Ensure paths don't contain special characters

### Debug Mode

Enable verbose logging by adding to your configuration:

```json
{
  "mcpServers": {
    "your-server": {
      "command": "your-command",
      "args": ["--verbose"],  // Add verbose flag if supported
      // ... rest of config
    }
  }
}
```

## Advanced Configuration

### Environment Variables

You can use environment variables in your configuration:

```json
{
  "mcpServers": {
    "github": {
      "env": {
        "GITHUB_TOKEN": "${GITHUB_MCP_TOKEN}",
        "GITHUB_API_URL": "https://api.github.com"
      }
    }
  }
}
```

### Multiple GitHub Accounts

For multiple GitHub accounts, create separate MCP servers:

```json
{
  "mcpServers": {
    "github-personal": {
      "command": "op",
      "args": ["run", "--", "npx", "-y", "@modelcontextprotocol/server-github"],
      "env": {
        "GITHUB_TOKEN": "op://PersonalVault/GitHub-Personal-Token/password"
      }
    },
    "github-work": {
      "command": "op",
      "args": ["run", "--", "npx", "-y", "@modelcontextprotocol/server-github"],
      "env": {
        "GITHUB_TOKEN": "op://WorkVault/GitHub-Work-Token/password"
      }
    }
  }
}
```

This setup provides secure, production-ready MCP integration for your development workflow!
