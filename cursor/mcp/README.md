# Model Context Protocol (MCP) Configurations

## Overview

MCP (Model Context Protocol) allows AI assistants like Cursor to access external tools and data sources directly. This directory contains production-ready MCP configurations for development and DevOps workflows.

## Repository Structure

```text
mcp/
├── README.md                   # This overview and setup guide
├── cursor/                     # Cursor-specific MCP configurations
│   ├── configuration.json      # Main MCP config (template)
│   ├── setup-guide.md         # Step-by-step Cursor setup
│   └── examples/              # Example configurations for different workflows
├── tools/                     # Individual MCP tool documentation
│   ├── terraform-tools.md     # Terraform/HCP integration
│   ├── kubernetes-tools.md    # Kubernetes management tools
│   ├── github-tools.md        # GitHub integration tools
│   └── filesystem-tools.md    # File system access tools
└── security/                  # Security and credentials management
    ├── 1password-integration.md # 1Password CLI integration
    └── environment-variables.md # Environment variable patterns
```

## Quick Start

1. **Choose your tools**: Review `tools/` directory for available MCP servers
2. **Configure Cursor**: Follow `cursor/setup-guide.md` for installation
3. **Adapt configuration**: Use `cursor/configuration.json` as template
4. **Set up credentials**: Follow `security/` guides for secure token management

## Supported MCP Servers

### Development Tools

- **GitHub**: Repository management, issue tracking, PR workflows
- **Filesystem**: Advanced file operations with security controls
- **Terraform**: Infrastructure management and HCP integration
- **Kubernetes**: Cluster management and resource operations

### Security Features

- **1Password CLI integration** for secure credential management
- **Path restrictions** for filesystem access
- **Environment variable** patterns for sensitive data

## Benefits

- **Secure credential handling** via 1Password CLI
- **Restricted filesystem access** to project directories only
- **Production-ready configurations** tested in real development workflows
- **Comprehensive documentation** for easy adaptation

## Prerequisites

- Cursor IDE with MCP support
- Node.js (for npm-based MCP servers)
- Go (for terraform-mcp-server)
- 1Password CLI (for secure credential management)
- Appropriate API tokens for integrated services
