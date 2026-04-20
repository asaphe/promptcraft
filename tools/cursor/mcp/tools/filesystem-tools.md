# Filesystem MCP Tools

## Overview

The Filesystem MCP server provides AI assistants with controlled access to local file systems, enabling file operations, directory navigation, and content analysis while maintaining security through path restrictions.

## Features

### File Operations

- Read, write, and modify files
- Create and delete files and directories
- Move and copy files
- Search file contents and patterns

### Directory Management

- Navigate directory structures
- List directory contents with filtering
- Create and manage directory hierarchies
- Monitor file system changes

### Content Analysis

- Search across multiple files
- Analyze code structure and dependencies
- Generate file and project summaries
- Detect patterns and anomalies

### Security Controls

- Restricted path access (only specified directories)
- Read-only vs read-write permissions
- File type filtering
- Size and operation limits

## Installation

The filesystem MCP server is available via npm:

```bash
# Global installation (optional)
npm install -g fast-filesystem-mcp

# Or use via npx (recommended)
npx fast-filesystem-mcp --help
```

## Configuration

### Basic Configuration

```json
{
  "mcpServers": {
    "filesystem": {
      "command": "npx",
      "args": [
        "-y",
        "fast-filesystem-mcp",
        "/path/to/your/projects"
      ]
    }
  }
}
```

### Multiple Directory Access

```json
{
  "mcpServers": {
    "filesystem": {
      "command": "npx",
      "args": [
        "-y",
        "fast-filesystem-mcp",
        "/Users/username/projects",
        "/Users/username/workspace",
        "/Users/username/Documents/work",
        "/Users/username/Downloads"
      ]
    }
  }
}
```

### Advanced Configuration with Options

```json
{
  "mcpServers": {
    "filesystem-advanced": {
      "command": "npx",
      "args": [
        "-y",
        "fast-filesystem-mcp",
        "--max-file-size=10MB",
        "--read-only=false",
        "--follow-symlinks=false",
        "/path/to/projects"
      ]
    }
  }
}
```

## Path Configuration Best Practices

### Development Setup

```json
{
  "args": [
    "-y",
    "fast-filesystem-mcp",
    "/Users/username/projects",        // Main development projects
    "/Users/username/workspace",       // Temporary workspace
    "/Users/username/.config",         // Configuration files
    "/Users/username/Documents/notes"  // Documentation and notes
  ]
}
```

### Project-Specific Setup

```json
{
  "args": [
    "-y",
    "fast-filesystem-mcp",
    "/Users/username/company-projects",     // Work projects only
    "/Users/username/company-tools",        // Company-specific tools
    "/Users/username/Documents/company"     // Company documentation
  ]
}
```

## Security Considerations

### Path Restrictions

**IMPORTANT**: Only include directories you want AI to access!

#### ✅ Safe Directories

- Project directories (`/Users/username/projects`)
- Workspace directories (`/Users/username/workspace`)
- Documentation directories (`/Users/username/Documents/work`)
- Configuration directories (`/Users/username/.config/project`)

#### ❌ Avoid These Directories

- Root directory (`/`)
- System directories (`/System`, `/usr`, `/bin`)
- Home directory root (`/Users/username`)
- Sensitive directories (`/Users/username/.ssh`, `/Users/username/.aws`)
- Cache directories (`/Users/username/.cache`)

### Permission Levels

#### Read-Only Access

```json
{
  "args": [
    "-y",
    "fast-filesystem-mcp",
    "--read-only=true",
    "/path/to/read-only/directory"
  ]
}
```

#### Read-Write Access (Default)

```json
{
  "args": [
    "-y",
    "fast-filesystem-mcp",
    "--read-only=false",  // Default
    "/path/to/writable/directory"
  ]
}
```

### File Type Filtering

```json
{
  "args": [
    "-y",
    "fast-filesystem-mcp",
    "--include-patterns=*.js,*.ts,*.py,*.md,*.json",
    "--exclude-patterns=node_modules,*.log,*.tmp",
    "/path/to/projects"
  ]
}
```

## Usage Examples

### Project Management

**Ask AI**: "Show me all TypeScript files in my current project that import 'react'"

**AI can**:

- Search across project directories
- Filter by file types and content
- Analyze import dependencies
- Generate project structure summaries

### Code Analysis

**Ask AI**: "Find all TODO comments in my codebase and prioritize them"

**AI can**:

- Search for comment patterns
- Extract and categorize TODOs
- Analyze context and urgency
- Generate actionable task lists

### File Organization

**Ask AI**: "Organize my Downloads folder by moving images to appropriate project directories"

**AI can**:

- Analyze file types and content
- Suggest appropriate destinations
- Move files with confirmation
- Create organizational structures

### Documentation Generation

**Ask AI**: "Generate README files for all my projects that don't have them"

**AI can**:

- Analyze project structure
- Identify missing documentation
- Generate appropriate README content
- Create consistent documentation standards

## Advanced Features

### Symlink Handling

```json
{
  "args": [
    "-y",
    "fast-filesystem-mcp",
    "--follow-symlinks=true",  // Follow symbolic links
    "/path/to/projects"
  ]
}
```

### File Size Limits

```json
{
  "args": [
    "-y",
    "fast-filesystem-mcp",
    "--max-file-size=50MB",    // Increase size limit
    "--max-files=10000",       // Limit number of files
    "/path/to/large-projects"
  ]
}
```

### Custom Ignore Patterns

```json
{
  "args": [
    "-y",
    "fast-filesystem-mcp",
    "--ignore-file=.gitignore",           // Use .gitignore patterns
    "--additional-ignore=*.log,tmp/,dist/", // Additional patterns
    "/path/to/projects"
  ]
}
```

## Integration Patterns

### With Git Repositories

```json
{
  "mcpServers": {
    "filesystem": {
      "command": "npx",
      "args": [
        "-y",
        "fast-filesystem-mcp",
        "--respect-gitignore=true",
        "--include-git-files=false",
        "/Users/username/git-projects"
      ]
    }
  }
}
```

### With Development Tools

**Combined with other MCP servers**:

```json
{
  "mcpServers": {
    "filesystem": {
      "command": "npx",
      "args": ["-y", "fast-filesystem-mcp", "/Users/username/projects"]
    },
    "github": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-github"],
      "env": {
        "GITHUB_TOKEN": "op://YourVault/GitHub-Token-Name/password"
      }
    }
  }
}
```

**Usage**: "Compare my local project files with the GitHub repository and identify differences"

## Troubleshooting

### Common Issues

**Permission denied errors**:

```bash
# Check directory permissions
ls -la /path/to/directory

# Fix permissions if needed
chmod 755 /path/to/directory

# Check if directory exists
test -d /path/to/directory && echo "exists" || echo "does not exist"
```

**Path not accessible**:

- Verify paths are absolute (start with `/`)
- Ensure directories exist before starting MCP server
- Check for typos in directory names
- Verify you have read/write permissions

**Performance issues**:

```json
{
  "args": [
    "-y",
    "fast-filesystem-mcp",
    "--max-files=1000",      // Limit number of files
    "--max-depth=5",         // Limit directory depth
    "--cache-duration=300",  // Cache results for 5 minutes
    "/path/to/large/project"
  ]
}
```

### Debug Mode

Enable verbose logging:

```json
{
  "mcpServers": {
    "filesystem": {
      "command": "npx",
      "args": [
        "-y",
        "fast-filesystem-mcp",
        "--verbose",
        "--log-level=debug",
        "/path/to/projects"
      ]
    }
  }
}
```

## Best Practices

### Directory Organization

1. **Use specific project directories** rather than entire home directory
2. **Group related projects** together
3. **Exclude temporary and cache directories**
4. **Use read-only access** for reference materials
5. **Regularly review and update** allowed paths

### Performance Optimization

1. **Limit directory depth** for large projects
2. **Use appropriate file size limits**
3. **Exclude binary files** when possible
4. **Enable caching** for frequently accessed directories

### Security Maintenance

1. **Regularly audit** accessible directories
2. **Remove unused** directory access
3. **Use principle of least privilege**
4. **Monitor file operation logs**

This filesystem MCP setup provides secure, controlled access to local files while maintaining the flexibility needed for AI-assisted development workflows!
