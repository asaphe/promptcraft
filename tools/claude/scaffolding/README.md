# Scaffolding: Example `.claude/` Directory

An optional infrastructure-oriented starter `.claude/` directory. Select it explicitly through the guarded [scaffold recipe](../../../ADOPTION.md#optional-infrastructure-project-scaffold), then customize before use. Review overlapping rules before combining it with the operations profile. Public repository links are optional upstream help, not runtime dependencies.

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
└── global-claude-md-example.md      # Pointer to baseline and advanced reference

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

1. **Select a project and use the guarded [scaffold recipe](../../../ADOPTION.md#optional-infrastructure-project-scaffold).** Existing `.claude/` configuration must be compared and merged manually.

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
   - Follow [global-claude-md-example.md](global-claude-md-example.md) to the canonical standalone baseline and guarded recipe.
   - Browse the advanced author profile separately; do not copy this pointer as configuration.

## What to Customize vs Keep

| Keep As-Is | Customize |
| --------- | --------- |
| Operational safety rules (universal) | Service names and registries |
| Edit discipline patterns | Module inventories |
| Failure analysis protocol | Workspace patterns |
| PR review routing structure | Deployment targets |
| Checkpoint skill structure | Auth profiles and credentials |
| Agent deferral pattern | Team-specific code standards |
