# GitHub MCP Tools

## Overview

The GitHub MCP server provides AI assistants with comprehensive access to GitHub repositories, issues, pull requests, and other GitHub features for seamless development workflow integration.

## Features

### Repository Management

- List, search, and explore repositories
- Access repository contents and file history
- Manage repository settings and collaborators
- Clone and fork repositories

### Issue & PR Management

- Create, update, and close issues
- Manage pull requests and reviews
- Search issues and PRs with advanced filters
- Access comments and discussions

### Code Operations

- Browse code across branches and commits
- Search code within repositories
- Access commit history and diffs
- Manage branches and tags

### CI/CD Integration

- Monitor GitHub Actions workflows
- Access build logs and artifacts
- Manage deployment status
- Review security alerts

## Installation

The GitHub MCP server is distributed via npm and doesn't require separate installation.

## Configuration

### Basic Configuration

```json
{
  "mcpServers": {
    "github": {
      "command": "npx",
      "args": [
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

### Advanced Configuration with 1Password CLI

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
        "GITHUB_TOKEN": "op://YourVault/GitHub-Token-Name/password",
        "GITHUB_API_URL": "https://api.github.com"
      }
    }
  }
}
```

### Enterprise GitHub Configuration

```json
{
  "mcpServers": {
    "github-enterprise": {
      "command": "op",
      "args": [
        "run",
        "--",
        "npx",
        "-y",
        "@modelcontextprotocol/server-github"
      ],
      "env": {
        "GITHUB_TOKEN": "op://WorkVault/GitHub-Enterprise-Token/password",
        "GITHUB_API_URL": "https://github.company.com/api/v3"
      }
    }
  }
}
```

## Authentication

### Creating GitHub Personal Access Token

1. **Go to GitHub Settings**:
   - Navigate to Settings → Developer settings → Personal access tokens → Tokens (classic)

2. **Generate New Token**:
   - Click "Generate new token (classic)"
   - Set expiration (90 days recommended)

3. **Select Scopes**:

   ```text
   ✅ repo                    # Full repository access
   ✅ read:org               # Read organization data
   ✅ read:user              # Read user profile data
   ✅ read:project           # Read project data (if using Projects)
   ✅ workflow               # Update GitHub Actions workflows (if needed)
   ✅ read:packages          # Read package data (if using GitHub Packages)
   ```

4. **Copy Token**: Save immediately (won't be shown again)

### Storing Token Securely

#### Option 1: 1Password CLI (Recommended)

```bash
# Create new API credential in 1Password
op item create \
  --category="API Credential" \
  --title="GitHub MCP Token" \
  --vault="Private" \
  --url="https://github.com" \
  username="your-github-username" \
  password="ghp_your_token_here"

# Test access
op item get "GitHub MCP Token" --fields password
```

#### Option 2: Environment Variable

```bash
# Add to your shell profile (~/.zshrc, ~/.bashrc)
export GITHUB_MCP_TOKEN="ghp_your_token_here"

# Update MCP configuration
{
  "env": {
    "GITHUB_TOKEN": "${GITHUB_MCP_TOKEN}"
  }
}
```

## Usage Examples

### Repository Operations

**Ask AI**: "List my recent repositories and their status"

**AI can**:

- Show repositories with recent activity
- Display commit counts and contributors
- Check CI/CD status
- Identify repositories needing attention

### Issue Management

**Ask AI**: "Create an issue for the bug I found in the authentication module"

**AI can**:

- Create detailed issues with proper labels
- Reference related issues or PRs
- Assign to appropriate team members
- Set milestones and projects

### Code Review

**Ask AI**: "Review the changes in PR #123 for security issues"

**AI can**:

- Analyze code changes in pull requests
- Identify potential security vulnerabilities
- Suggest improvements
- Check for coding standard compliance

### Project Planning

**Ask AI**: "Show me all open issues labeled 'bug' across my organization"

**AI can**:

- Search across multiple repositories
- Filter by labels, milestones, assignees
- Generate reports and summaries
- Track progress over time

## Best Practices

### Security

- **Use minimum required scopes** for tokens
- **Rotate tokens regularly** (every 90 days)
- **Store tokens securely** using 1Password or similar
- **Monitor token usage** through GitHub audit logs
- **Use separate tokens** for different purposes

### Performance

- **Cache frequently accessed data** when possible
- **Use GraphQL API** for complex queries (when available)
- **Batch operations** to avoid rate limiting
- **Implement exponential backoff** for retries

### Organization

- **Use clear naming** for multiple GitHub configurations
- **Document token purposes** and permissions
- **Set up proper alerting** for token expiration
- **Use team tokens** for shared resources when appropriate

## Multiple Account Setup

### Personal + Work Accounts

```json
{
  "mcpServers": {
    "github-personal": {
      "command": "op",
      "args": ["run", "--", "npx", "-y", "@modelcontextprotocol/server-github"],
      "env": {
        "GITHUB_TOKEN": "op://PersonalVault/GitHub-Personal-Token/password",
        "GITHUB_API_URL": "https://api.github.com"
      }
    },
    "github-work": {
      "command": "op",
      "args": ["run", "--", "npx", "-y", "@modelcontextprotocol/server-github"],
      "env": {
        "GITHUB_TOKEN": "op://WorkVault/GitHub-Work-Token/password",
        "GITHUB_API_URL": "https://api.github.com"
      }
    }
  }
}
```

### Usage with Multiple Accounts

**Ask AI**: "Show me issues from my work repositories"

- AI can distinguish between different GitHub accounts
- Filter results based on the specific account
- Maintain separate contexts for each account

## Troubleshooting

### Common Issues

**Authentication failures**:

```bash
# Test token manually
curl -H "Authorization: Bearer $GITHUB_TOKEN" \
     https://api.github.com/user

# Check 1Password access
op item get "GitHub MCP Token" --fields password

# Verify token scopes
# Go to GitHub → Settings → Personal access tokens → View token
```

**Rate limiting**:

- GitHub has rate limits (5,000 requests/hour for authenticated users)
- Use GraphQL for complex queries
- Implement caching where appropriate
- Monitor usage through GitHub's rate limit headers

**Network connectivity**:

```bash
# Test GitHub API connectivity
curl -I https://api.github.com

# For enterprise GitHub
curl -I https://github.company.com/api/v3
```

### Debug Mode

Enable verbose logging:

```json
{
  "mcpServers": {
    "github": {
      "command": "npx",
      "args": [
        "-y",
        "@modelcontextprotocol/server-github",
        "--verbose"
      ],
      "env": {
        "DEBUG": "github-mcp:*",
        "GITHUB_TOKEN": "op://YourVault/GitHub-Token-Name/password"
      }
    }
  }
}
```

## Advanced Features

### Webhook Integration

For real-time updates, consider setting up webhooks:

```json
{
  "env": {
    "GITHUB_WEBHOOK_SECRET": "op://YourVault/GitHub-Webhook-Secret/password",
    "GITHUB_WEBHOOK_URL": "https://your-webhook-endpoint.com/github"
  }
}
```

### Custom API Endpoints

For specialized GitHub integrations:

```json
{
  "env": {
    "GITHUB_GRAPHQL_URL": "https://api.github.com/graphql",
    "GITHUB_UPLOAD_URL": "https://uploads.github.com",
    "GITHUB_API_VERSION": "2022-11-28"
  }
}
```

This setup provides comprehensive GitHub integration for AI-assisted development workflows!
