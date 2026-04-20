# Scaffolding: Example `.claude/` Directory

A complete, anonymized example of a production `.claude/` directory structure. Copy this to your repository and customize.

## Directory Structure

```text
scaffolding/
├── .claude/
│   ├── CLAUDE.md                    # Project navigation hub (auto-loaded)
│   ├── agents/                      # Specialist subagents
│   │   ├── infra-expert.md         # Infrastructure Terraform specialist
│   │   └── devops-reviewer.md      # Read-only DevOps PR reviewer
│   ├── rules/                       # Auto-loaded operational rules
│   │   ├── operational-safety.md   # Session management, edit discipline, failure analysis
│   │   ├── terraform-apply.md      # Terraform plan/apply safety
│   │   └── pr-review.md           # PR review routing and posting
│   ├── skills/                      # User-invocable slash commands
│   │   ├── deploy/SKILL.md        # /deploy — trigger deployment workflow
│   │   ├── verify-deploy/SKILL.md # /verify-deploy — post-deploy health check
│   │   └── checkpoint/SKILL.md    # /checkpoint — session state snapshot
│   ├── docs/                        # On-demand reference (not auto-loaded)
│   │   ├── agent-roster.md        # Central agent deferral table
│   │   └── architecture.md        # Service inventory, databases, structure
│   └── specs/                       # Standards and specifications
│       └── ci-cd-spec.md          # RFC-style CI/CD rules
└── global-claude-md-example.md      # Example ~/.claude/CLAUDE.md

```

## How the Pieces Fit Together

```text
┌─────────────────────────────────────────────────────┐
│  ~/.claude/CLAUDE.md (global)                       │
│  Cross-project: commit policy, auth, safety rules   │
└──────────────────────┬──────────────────────────────┘
                       │ always loaded
┌──────────────────────▼──────────────────────────────┐
│  .claude/CLAUDE.md (project)                        │
│  Navigation hub: agent roster, code standards,      │
│  pointers to on-demand docs                         │
│  ┌─────────────────────────────────────────────┐    │
│  │  .claude/rules/*.md (auto-loaded)           │    │
│  │  Operational rules from real incidents       │    │
│  └─────────────────────────────────────────────┘    │
└──────────────────────┬──────────────────────────────┘
                       │ loaded when invoked
┌──────────────────────▼──────────────────────────────┐
│  .claude/agents/*.md (loaded per-agent)             │
│  Specialist agents with domain knowledge            │
│                                                     │
│  .claude/skills/*/SKILL.md (loaded per-command)     │
│  Interactive workflows via /command                  │
│                                                     │
│  .claude/docs/*.md (loaded on-demand)               │
│  Reference material read when needed                │
│                                                     │
│  .claude/specs/*.md (loaded on-demand)              │
│  Standards and specifications                       │
└─────────────────────────────────────────────────────┘
```

## Loading Behavior

| Location | When Loaded | Token Cost |
| -------- | ----------- | ---------- |
| `CLAUDE.md` | Every conversation | Always (keep lean) |
| `.claude/rules/*.md` | Every conversation | Always (keep to single bullets) |
| `.claude/agents/*.md` | When agent is invoked | Per-agent (okay to be detailed) |
| `.claude/skills/*/SKILL.md` | When user types `/command` | Per-skill |
| `.claude/docs/*.md` | When agent calls `Read` | On-demand (can be large) |
| `.claude/specs/*.md` | When agent calls `Read` | On-demand (can be large) |

## Quick Start

1. **Copy the `.claude/` directory to your repo root:**

   ```bash
   cp -r scaffolding/.claude /path/to/your/repo/
   ```

2. **Customize `CLAUDE.md`:**
   - Replace `<placeholder>` service names with your actual services
   - Update the agent roster to match your agents
   - Add your code standards

3. **Customize agents:**
   - Update module inventories and failure triage tables
   - Adjust scope constraints and sibling deferral tables
   - Add domain-specific knowledge

4. **Customize skills:**
   - Update valid applications lists
   - Adjust workflow file names and registry commands
   - Add project-specific safety rules

5. **Add your rules:**
   - Start with `operational-safety.md` (universal patterns)
   - Add domain rules as incidents teach you lessons
   - Format: `- **Rule title** — What to do and why.`

6. **Set up global config:**
   - Copy `global-claude-md-example.md` to `~/.claude/CLAUDE.md`
   - Customize with your auth profiles, commit policy, and preferences

## What to Customize vs Keep

| Keep As-Is | Customize |
| --------- | --------- |
| Operational safety rules (universal) | Service names and registries |
| Edit discipline patterns | Module inventories |
| Failure analysis protocol | Workspace patterns |
| PR review routing structure | Deployment targets |
| Checkpoint skill structure | Auth profiles and credentials |
| Agent deferral pattern | Team-specific code standards |
