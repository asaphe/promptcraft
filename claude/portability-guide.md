# Claude Code Portability Guide

How to make your Claude Code configuration portable across machines using dotfiles, symlinks, and backups.

## The Problem

Claude Code stores configuration in `~/.claude/`, but most of that directory is ephemeral (cache, telemetry, session data). The valuable files — your global CLAUDE.md, settings, docs, commands, and memory — are mixed in with runtime state. Without a portability strategy, a new machine means rebuilding your setup from scratch.

Additionally, Claude Desktop (the Electron app) has its own separate config at `~/Library/Application Support/Claude/` (macOS) that isn't part of `~/.claude/`.

## Architecture: Two Separate Config Systems

Claude Code and Claude Desktop are **completely independent** configuration systems:

| Aspect | Claude Code (CLI) | Claude Desktop (App) |
|--------|------------------|---------------------|
| Main config | `~/.claude/settings.json` | `~/Library/Application Support/Claude/claude_desktop_config.json` |
| Project config | `.claude/settings.json` (git-tracked) | N/A |
| Local overrides | `~/.claude/settings.local.json` | N/A |
| MCP servers | `~/.claude.json` (user) or `.mcp.json` (project) | `mcpServers` in desktop config |
| Permissions | `permissions.allow/deny` arrays with glob patterns | Interactive UI |
| Hooks | `hooks` object with lifecycle events | N/A |
| Behavioral rules | `~/.claude/CLAUDE.md` | N/A |

Changes to one system do **not** affect the other. You must manage them separately.

## Claude Desktop Config Reference

The `claude_desktop_config.json` file supports:

```json
{
  "mcpServers": {
    "server-name": {
      "command": "npx",
      "args": ["package-name", "arg1"],
      "env": { "API_KEY": "..." }
    }
  },
  "preferences": {
    "ccBranchPrefix": "DEV-",
    "localAgentModeTrustedFolders": ["/path/to/trusted"],
    "coworkScheduledTasksEnabled": true,
    "ccdScheduledTasksEnabled": true,
    "coworkWebSearchEnabled": true,
    "sidebarMode": "chat"
  }
}
```

Most meaningful customization lives in Claude Code's `~/.claude/` directory, not Desktop.

## Symlink Strategy

### What to Symlink

These files contain your accumulated configuration and should live in your dotfiles repo.

In the table and scripts below, `$DOTFILES_DIR` is the `claude/` subdirectory of your dotfiles repo. Common layouts:

| Convention | `$DOTFILES_DIR` |
|-----------|----------------|
| `~/.dotfiles` (hidden) | `~/.dotfiles/claude` |
| `~/dotfiles` (visible) | `~/dotfiles/claude` |
| `~/code/dotfiles` | `~/code/dotfiles/claude` |

| File/Directory | Purpose | Symlink Target |
|---------------|---------|---------------|
| `CLAUDE.md` | Global behavioral rules | `$DOTFILES_DIR/CLAUDE.md` |
| `settings.json` | Permissions, hooks, env vars | `$DOTFILES_DIR/settings.json` |
| `docs/` | On-demand reference docs | `$DOTFILES_DIR/docs/` |
| `commands/` | Custom slash commands | `$DOTFILES_DIR/commands/` |
| `statusline-command.sh` | Status line customization | `$DOTFILES_DIR/statusline-command.sh` |
| `LOCAL_SENSITIVE.md` | Machine-local sensitive reference (see below) | `$DOTFILES_DIR/LOCAL_SENSITIVE.md` |
| `memory/` | Persistent auto-memory | `$DOTFILES_DIR/memory/` |
| `scripts/` | Utility scripts used by hooks | `$DOTFILES_DIR/scripts/` |

### What NOT to Symlink

These are ephemeral, machine-specific, or auto-generated:

| File/Directory | Why Skip |
|---------------|----------|
| `history.jsonl` | Large conversation log, machine-specific |
| `cache/`, `debug/`, `file-history/` | Runtime cache |
| `paste-cache/`, `session-env/`, `shell-snapshots/` | Session-specific |
| `projects/` | Per-project auto-generated state |
| `plans/`, `todos/`, `tasks/` | Session-specific |
| `stats-cache.json`, `statsig/`, `telemetry/` | App internals |
| `chrome/`, `ide/`, `plugins/`, `backups/` | Runtime state |
| `settings.local.json` | Machine-specific permission overrides |

### Setup Script

```bash
#!/usr/bin/env bash
set -euo pipefail

# Set to the claude/ subdirectory of your dotfiles repo.
# Common: "$HOME/.dotfiles/claude" or "$HOME/dotfiles/claude"
DOTFILES_DIR="${DOTFILES_DIR:-$HOME/.dotfiles/claude}"
CLAUDE_DIR="$HOME/.claude"

mkdir -p "$DOTFILES_DIR/docs" "$DOTFILES_DIR/commands" "$DOTFILES_DIR/memory" "$DOTFILES_DIR/scripts"

# Files to symlink
SYMLINKS=(
  "CLAUDE.md"
  "settings.json"
  "docs"
  "commands"
  "statusline-command.sh"
  "LOCAL_SENSITIVE.md"
  "memory"
  "scripts"
)

for item in "${SYMLINKS[@]}"; do
  source="$CLAUDE_DIR/$item"
  target="$DOTFILES_DIR/$item"

  # If source exists and is not already a symlink, move it to dotfiles
  if [[ -e "$source" && ! -L "$source" ]]; then
    if [[ -e "$target" ]]; then
      echo "WARNING: $target already exists, skipping move of $source"
      continue
    fi
    mv "$source" "$target"
  fi

  # Create symlink if target exists
  if [[ -e "$target" && ! -L "$source" ]]; then
    ln -sf "$target" "$source"
    echo "Linked: $source -> $target"
  fi
done
```

## The LOCAL_SENSITIVE.md Pattern

Some reference material is valuable on every machine but shouldn't be committed to a shared repo (account IDs, resource ARNs, internal paths). The `LOCAL_SENSITIVE.md` file solves this:

```markdown
# LOCAL SENSITIVE CONFIGURATION

**DO NOT COMMIT THIS FILE TO ANY REPOSITORY**

## Cloud Account Information

| Account | ID | Profile | Purpose |
|---------|-----|---------|---------|
| dev | 123456789012 | `dev` | Development |
| prod | 210987654321 | `prod` | Production |

## Local Paths

- Docs: `~/path/to/docs/`
- Clones: `~/projects/repo`, `~/projects/repo-2`

## Common Resources

- State bucket: `my-terraform-states`
- Cluster: `prod-cluster-01`
```

This file:
- Lives in your dotfiles (private repo or encrypted)
- Is symlinked into `~/.claude/` so Claude Code can read it
- Is NOT committed to any project repo
- Contains machine-context that helps Claude make correct assumptions

## `settings.local.json` — Machine-Specific Overrides

Claude Code supports `settings.local.json` for per-machine permission overrides that aren't shared with the team. This file is auto-created when you approve tool calls locally.

Over time it accumulates specific permission entries. Periodically clean it up by replacing granular entries with broader wildcards:

```json
{
  "permissions": {
    "allow": [
      "Bash(terraform:*)",
      "Bash(kubectl:*)",
      "Bash(aws:*)"
    ]
  }
}
```

This file should NOT be symlinked (it's machine-specific) and should NOT be committed to any repo.

## Backup Strategy

For files that shouldn't be symlinked but are still valuable (plans, project-specific memory), use a periodic backup:

```bash
#!/usr/bin/env bash
set -euo pipefail

BACKUP_DIR="$HOME/path/to/backup/claude-backup"
mkdir -p "$BACKUP_DIR"

rsync -av --delete \
  --include='CLAUDE.md' \
  --include='LOCAL_SENSITIVE.md' \
  --include='settings.json' \
  --include='settings.local.json' \
  --include='statusline-command.sh' \
  --include='docs/***' \
  --include='commands/***' \
  --include='memory/***' \
  --include='skills/***' \
  --include='plans/***' \
  --exclude='*' \
  "$HOME/.claude/" "$BACKUP_DIR/"

# Also back up Claude Desktop config (macOS)
rsync -av \
  "$HOME/Library/Application Support/Claude/claude_desktop_config.json" \
  "$BACKUP_DIR/claude_desktop_config.json" 2>/dev/null || true

echo "Backup complete: $BACKUP_DIR"
```

Run manually, via cron, or as a git hook in your dotfiles repo.

## Multi-Clone Awareness

When working with multiple clones of the same repository, add clone awareness to your global CLAUDE.md:

```markdown
## Multiple Repository Clones

The user has multiple clones: `~/projects/repo` (primary), `repo-2`, `repo-3`.

- Always identify which clone at the start of work
- Be explicit about paths when referencing files across clones
- Don't assume which clone — ask if unclear
```

This prevents Claude from making assumptions about which working copy you're in, which matters when clones may be on different branches or have different local state.

## Config Layering Summary

```text
~/.claude/settings.json          (shared via dotfiles — base permissions, hooks, env)
  + ~/.claude/settings.local.json (machine-only — local permission overrides)
  + .claude/settings.json         (project — team-shared via git)
  + .claude/settings.local.json   (project, machine-only — .gitignored)
```

Each layer adds to (or overrides) the previous. The global `settings.json` in dotfiles is your foundation; project and local layers customize on top.

## Checklist: New Machine Setup

1. Clone your dotfiles repo
2. Run the symlink setup script
3. Create `~/.claude/settings.local.json` with machine-specific permissions (or let it auto-populate)
4. Verify: `ls -la ~/.claude/CLAUDE.md` should show the symlink
5. Open Claude Code — your full config should be active immediately
6. Configure Claude Desktop separately (`claude_desktop_config.json`)
