# MCP Server Management Guide

How to add, remove, and manage Model Context Protocol (MCP) servers in Claude Code and Claude Desktop — including team-wide connectors and common pitfalls.

## MCP Configuration Locations

MCP servers can be configured at multiple levels, and each level is managed differently:

| Scope | Location | Shared? | Managed By |
|-------|----------|---------|------------|
| **User (Code)** | `~/.claude.json` | No | `claude mcp add -s user` |
| **Project (Code)** | `.mcp.json` in project root | Yes (git) | `claude mcp add -s project` |
| **Desktop** | `~/Library/Application Support/Claude/claude_desktop_config.json` | No | Manual edit |
| **Org connector** | claude.ai web UI | Yes (org-wide) | Org admin via web UI |

### Scope Precedence

When the same MCP server name exists at multiple levels, the most specific scope wins:

```text
Org connector (always active for all org members)
  └── User scope (active in all your projects)
       └── Project scope (active only in this repo)
```

## Adding MCP Servers

### Claude Code (CLI)

```bash
# User-scoped (all projects)
claude mcp add --transport http -s user my-server https://server.example.com/mcp

# Project-scoped (this repo only, committed to git)
claude mcp add --transport http -s project my-server https://server.example.com/mcp

# With stdio transport (local process)
claude mcp add -s user my-local-server npx my-mcp-package
```

### Claude Desktop

Edit `~/Library/Application Support/Claude/claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "my-server": {
      "command": "npx",
      "args": ["mcp-remote", "https://server.example.com/mcp"]
    }
  }
}
```

Restart Claude Desktop after editing.

### Organization Connector (Team-Wide)

Org connectors are added via the claude.ai web UI:

1. Go to **claude.ai** → **Settings** → **Connectors** (or **Integrations**)
2. Click **Add Connector** / **Add MCP Server**
3. Enter the server URL
4. Complete any OAuth flow if the server requires authentication
5. The connector is now active for all org members

## Removing MCP Servers

### Claude Code

```bash
# List current servers
claude mcp list

# Remove by name and scope
claude mcp remove -s user my-server
claude mcp remove -s project my-server
```

### Claude Desktop

Edit `claude_desktop_config.json` and remove the server entry from `mcpServers`:

```json
{
  "mcpServers": {}
}
```

### Organization Connector

This is the tricky one. Org connectors are managed through the claude.ai web UI, not the CLI:

1. Go to **claude.ai** → **Settings** → **Connectors**
2. Find the connector
3. Look for a remove/disconnect option (may be behind a gear icon, three-dot menu, or inside the connector details)

If you cannot find the remove button, you can use the claude.ai API directly. Open your browser console while logged into claude.ai and run:

```javascript
// First, list connectors to find the server ID
const orgId = 'your-org-id';
const resp = await fetch(`/api/organizations/${orgId}/mcp/servers`);
const servers = await resp.json();
console.log(servers);

// Then delete by server ID
const serverId = 'server-id-from-above';
await fetch(`/api/organizations/${orgId}/mcp/servers/${serverId}`, {
  method: 'DELETE'
});
```

**Finding your org ID:** Check the URL when you're in your org settings, or look at any API request in the browser's Network tab.

## Common Pitfalls

### Ghost Servers

If an MCP server appears in Claude but you can't find it in any config file, check all four locations:

```bash
# Check Claude Code user config
cat ~/.claude.json 2>/dev/null

# Check project config
cat .mcp.json 2>/dev/null

# Check Desktop config
cat ~/Library/Application\ Support/Claude/claude_desktop_config.json

# Check if it's an org connector (web UI only)
# Go to claude.ai → Settings → Connectors
```

### Auth Errors on Org Connectors

Org connectors with OAuth may fail if:
- The OAuth token expired
- The server's redirect URI doesn't match
- The server is down or unreachable

The error typically looks like: "There was an error connecting to the MCP server. Please check your server URL and make sure your server handles auth correctly."

To fix: disconnect and reconnect the connector, or have the server admin verify the OAuth configuration.

### Duplicate Servers

Having the same server at multiple scopes causes confusion. If a server is added as both a user-scope Code server and a Desktop server, you'll see it twice with potentially different behavior. Decide on one canonical location per server.

### Context Window Impact

Each MCP server's tool definitions consume context tokens. A server with 20+ tools can use 5,000-10,000 tokens just for tool descriptions. Follow the principle from the [best practices guide](claude-best-practices.md): keep total MCP tool definitions under 20,000 tokens.

## Team MCP Strategy

### When to Use Org Connectors

- The server is **team-shared infrastructure** (internal database gateway, shared API proxy)
- **Every team member** needs access
- The server has **proper auth** (OAuth, API keys managed centrally)

### When to Use Project-Level Config

- The server is **specific to one repo** (e.g., a project's documentation search)
- You want the config **version-controlled** with the project
- Different projects need **different servers**

### When to Use User-Level Config

- The server is **personal tooling** (your database explorer, your note-taking system)
- You want it available **across all projects** but not imposed on teammates
- The server requires **personal credentials**

## MCP vs CLI Tools

Not everything should be an MCP server. Use MCP for:
- **Stateful connections** (database sessions, browser automation, authenticated APIs)
- **Shared team infrastructure** (org-wide gateways)

Use CLI tools documented in skills for:
- **Stateless operations** (file processing, formatting, linting)
- **One-off queries** (`aws`, `kubectl`, `terraform`)
- **Personal utilities** (anything only you use)

The rule of thumb: if `claude mcp add` is harder than `Bash(my-tool arg)`, it doesn't need to be an MCP server.
