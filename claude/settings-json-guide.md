# Claude Code Settings JSON Guide

`settings.json` controls Claude Code's runtime behavior: permissions, environment variables, hooks, and model preferences. It's the "how" complement to CLAUDE.md's "what/why."

## File Locations and Layering

Settings load in order, with later layers overriding earlier ones:

| Layer | Path | Scope | Committed to Git? |
|-------|------|-------|-------------------|
| Global | `~/.claude/settings.json` | All projects | No (personal machine config) |
| Project | `.claude/settings.json` | This repo | Yes (shared team config) |
| Local | `.claude/settings.local.json` | This repo, this machine | No (gitignored, personal overrides) |

### When to Use Each Layer

- **Global** — Personal preferences, tool permissions you always want, credential-related hooks
- **Project** — Team-wide standards: required hooks, permission defaults, environment variables the project needs
- **Local** — Personal overrides that shouldn't affect teammates (editor preferences, experimental hooks)

## Permissions

Permissions control which tools Claude can use without asking:

```json
{
  "permissions": {
    "allow": [
      "Read",
      "Glob",
      "Grep",
      "Bash(npm test:*)",
      "Bash(git status:*)",
      "Bash(git diff:*)",
      "Bash(git log:*)"
    ],
    "deny": [
      "Bash(rm -rf:*)",
      "Bash(git push --force:*)"
    ]
  }
}
```

### Permission Patterns

| Pattern | Matches |
|---------|---------|
| `"Bash"` | All Bash commands (broad — use cautiously) |
| `"Bash(*)"` | All Bash commands (equivalent) |
| `"Bash(npm test:*)"` | Bash commands starting with `npm test` |
| `"Bash(git *:*)"` | Bash commands starting with `git` |
| `"Read"` | All file reads |

### Wildcard Strategy

For experienced users who want maximum autonomy:

```json
{
  "permissions": {
    "allow": ["Bash(*)"],
    "deny": [
      "Bash(rm -rf *:*)",
      "Bash(git push --force*:*)",
      "Bash(git reset --hard*:*)"
    ]
  }
}
```

This allows all Bash commands except explicitly dangerous ones. Pair with PreToolUse hooks for additional guardrails.

## Environment Variables

Pass environment variables to Claude Code sessions:

```json
{
  "env": {
    "AWS_PROFILE": "dev",
    "TF_CLI_ARGS_plan": "-compact-warnings",
    "NODE_ENV": "development"
  }
}
```

Use project-level settings for variables the whole team needs. Use local settings for personal values.

## Hooks

See [hooks-guide.md](hooks-guide.md) for detailed hook design patterns. The settings structure:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": ".claude/hooks/validate-bash.sh"
          }
        ]
      }
    ]
  }
}
```

## Model Preferences

```json
{
  "model": "opus",
  "smallModelOverride": "haiku"
}
```

## MCP Servers

Configure MCP servers that Claude Code can connect to:

```json
{
  "mcpServers": {
    "browser": {
      "command": "npx",
      "args": ["-y", "@anthropic/mcp-browser"],
      "env": {}
    }
  }
}
```

### MCP in Global vs Project

- **Global** — Servers you always want (browser automation, personal tools)
- **Project** — Servers the team uses (project-specific APIs, databases)
- Avoid duplicating servers across layers — project-level takes precedence

## Design Principles

### Separate "What/Why" from "How"

| Concern | Where It Goes |
|---------|--------------|
| Coding standards, behavioral rules, project context | CLAUDE.md |
| Permissions, hooks, env vars, MCP servers | settings.json |
| Personal overrides | settings.local.json |

CLAUDE.md is a document Claude reads for guidance. settings.json is a configuration file that Claude Code's runtime enforces. Don't mix them.

### Start Minimal, Add on Failure

Don't pre-configure permissions and hooks for every scenario. Start with defaults and add rules when:

- Claude repeatedly asks for permission you want to auto-approve
- A dangerous command gets through that should have been blocked
- A quality gate (tests, lint) keeps being skipped

### Portability

- Global settings are machine-specific — back them up via dotfiles repo
- Project settings are committed — they travel with the repo
- Local settings are gitignored — they don't affect teammates
- Use `~/.claude/settings.json` symlinked from a dotfiles repo for multi-machine consistency

## Example: Full Project Configuration

```json
{
  "permissions": {
    "allow": [
      "Read",
      "Glob",
      "Grep",
      "Bash(npm *:*)",
      "Bash(git status:*)",
      "Bash(git diff:*)",
      "Bash(git log:*)",
      "Bash(terraform plan:*)",
      "Bash(terraform fmt:*)"
    ],
    "deny": [
      "Bash(terraform apply:*)",
      "Bash(terraform destroy:*)",
      "Bash(git push --force:*)"
    ]
  },
  "env": {
    "TF_CLI_ARGS_plan": "-compact-warnings"
  },
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash(*git commit*)",
        "hooks": [
          {
            "type": "command",
            "command": ".claude/hooks/pre-commit-gate.sh"
          }
        ]
      }
    ]
  }
}
```

## Related Resources

- [Hooks Guide](hooks-guide.md) — Detailed hook design patterns
- [Global CLAUDE.md Guide](global-claude-md-guide.md) — Designing the "what/why" complement
- [Portability Guide](portability-guide.md) — Backup, symlinks, and multi-machine setup
- [Best Practices](claude-best-practices.md) — How settings fit into the overall workflow
