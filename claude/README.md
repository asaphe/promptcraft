# Claude Code Documentation Templates

This directory contains production-tested templates for organizing Claude Code documentation in your repositories.

## Directory Structure

```text
claude/
├── agents/                     # Subagent design and templates
│   ├── agent-design-guide.md         # How to design Claude Code subagents
│   └── agent-template.md            # Ready-to-use agent template
├── rules/                      # Operational rules system
│   └── operational-rules-guide.md    # How to design and maintain auto-loaded rules
├── skills/                     # Skill (slash command) design
│   ├── skill-design-guide.md         # How to design Claude Code skills
│   └── skill-template.md            # Ready-to-use skill template
├── project-templates/          # Ready-to-use documentation templates
│   ├── navigation-hub.md             # Central navigation/overview
│   ├── codebase-guide-template.md    # Development workflows & architecture
│   ├── github-actions-guide.md       # GitHub Actions best practices
│   └── devops-infrastructure-guide.md # Terraform, K8s, infrastructure
├── specs/                      # Detailed specifications
│   └── ci-cd-specification.md        # RFC-style CI/CD standards
├── scaffolding/                # Complete example .claude/ directory (copy and customize)
│   ├── .claude/               # Example project config with agents, rules, skills, docs
│   └── global-claude-md-example.md  # Example ~/.claude/CLAUDE.md
├── claude-best-practices.md    # End-to-end best practices guide (context, planning, tools, workflow)
├── global-claude-md-guide.md   # How to design personal ~/.claude/CLAUDE.md
├── portability-guide.md        # Dotfiles, symlinks, backups, Desktop vs Code config
├── mcp-management-guide.md     # MCP server lifecycle: add, remove, team connectors, pitfalls
├── pr-review-protocol.md       # Structured PR review routing and posting
└── README.md                   # This file

Note: Cursor IDE rules are in ../cursor/mdc-rules/ (existing structure)
See also: ../core/agent-design-patterns.md for tool-agnostic agent design principles
```

## Templates Overview

### Subagent Design (`agents/`)

Guides and templates for building Claude Code specialist subagents (`.claude/agents/*.md`).

#### agent-design-guide.md

**Purpose:** Comprehensive guide for designing Claude Code subagents

**Features:**

- YAML frontmatter specification (name, description, tools, model, memory)
- System prompt structure (10 recommended sections)
- Model and tool selection guides
- Sizing guidelines and common mistakes
- Central roster and CLAUDE.md integration patterns

**Use When:** Creating new subagents, restructuring existing ones, or onboarding team members to the agent system

#### agent-template.md

**Purpose:** Ready-to-copy template for a new agent

**Features:**

- Complete YAML frontmatter with all fields
- All 10 recommended sections with placeholder text
- Customization checklist
- Model and tool selection reference tables

**Use When:** Creating a new `.claude/agents/<name>.md` file

**See Also:** `../core/agent-design-patterns.md` for tool-agnostic principles (when to split agents, cross-agent deferral patterns, failure triage table design)

#### review-agent-trio.md

**Purpose:** Pattern for splitting PR review into specialized domain agents

**Features:**

- Why a single reviewer produces shallow findings
- How to split by correction-frequency domains
- Agent design (tools, model, maxTurns) for read-only reviewers
- Orchestration via skills or main session
- File routing patterns
- Finding quality protocol (self-verification, present-before-posting)
- Scaling guidelines (when to add/merge reviewers)

**Use When:** Setting up AI-assisted PR reviews, scaling beyond a single reviewer agent

### Operational Rules (`rules/`)

Guides for the `.claude/rules/` auto-loaded operational rules system.

#### operational-rules-guide.md

**Purpose:** How to design, capture, and maintain auto-loaded operational rules

**Features:**

- What rules are (auto-loaded lessons from real incidents)
- Rules vs docs vs specs (auto-loaded vs on-demand)
- Rule format: `- **Rule title** — What to do and why.`
- Capture protocol (recognize, propose, classify, format, commit)
- Classification guide (agent-specific vs team-wide vs project vs global)
- Example rule categories and anti-patterns
- Session mining concept (scanning history for uncodified patterns)

**Use When:** Setting up a rules system, training team members on rule capture, or reviewing rule quality

### Skills (`skills/`)

Guides and templates for building Claude Code skills (user-invocable slash commands).

#### skill-design-guide.md

**Purpose:** Comprehensive guide for designing Claude Code skills

**Features:**

- What skills are (interactive workflows via `/command`)
- YAML frontmatter specification (name, description, allowed-tools, argument-hint)
- System prompt structure (steps, parameter resolution, safety)
- Skill vs agent decision matrix
- Design patterns (parameterized workflows, confirmation gates, multi-step verification)
- Common archetypes (deploy, verify, inspect, scaffold, checkpoint)
- Sizing guidelines and common mistakes

**Use When:** Creating new skills, deciding between skills and agents, or reviewing skill design

#### skill-template.md

**Purpose:** Ready-to-copy template for a new skill

**Features:**

- Complete YAML frontmatter with all fields
- Standard sections (parameter resolution, execution, results, safety)
- Customization checklist
- Tool selection guide

**Use When:** Creating a new `.claude/skills/<name>/SKILL.md` file

### Best Practices Guide

#### claude-best-practices.md

**Purpose:** End-to-end guide for getting the most out of Claude Code

**Features:**

- Context management (CLAUDE.md sizing, clearing strategies, token budgets)
- Planning workflow (Explore → Plan → Code → Commit)
- Quality gates (TDD, hooks, code review patterns)
- Tool strategy (skills auto-activation, MCP design, subagent patterns)
- Workflow optimization (course correction, visual references, worktrees, headless mode)
- Production lessons (decision checkpoints, finding verification, operational safety)
- Getting started progression (4-week plan)
- Success metrics (context efficiency, code quality, productivity)
- Anti-patterns to avoid

**Use When:** Onboarding to Claude Code, establishing team practices, or reviewing workflow effectiveness

### Global CLAUDE.md Guide

#### global-claude-md-guide.md

**Purpose:** How to design the personal `~/.claude/CLAUDE.md`

**Features:**

- What the global CLAUDE.md is (cross-project behavioral layer)
- What belongs in global vs project CLAUDE.md
- Common rule categories (commit policy, dangerous commands, auth, verification, scope discipline)
- Ready-to-use template
- Anti-patterns (project-specific content in global, duplication, bloat)

**Use When:** Setting up a new global config, reviewing what should be global vs project-specific

### Portability Guide

#### portability-guide.md

**Purpose:** How to make Claude Code config portable across machines

**Features:**

- Claude Code vs Claude Desktop configuration comparison
- Claude Desktop config reference (all known `preferences` keys)
- Symlink strategy (what to symlink vs skip, setup script)
- `LOCAL_SENSITIVE.md` pattern for machine-local secrets reference
- `settings.local.json` for machine-specific overrides
- Backup script for valuable non-symlinked files
- Multi-clone awareness pattern
- Config layering summary (global → project → local)
- New machine setup checklist

**Use When:** Setting up Claude Code on a new machine, creating a dotfiles strategy, understanding config portability

### MCP Management Guide

#### mcp-management-guide.md

**Purpose:** Complete lifecycle for MCP servers — adding, removing, and team management

**Features:**

- Four configuration scopes (user, project, desktop, org connector)
- Adding servers at each scope
- Removing servers (including org connectors via API)
- Common pitfalls (ghost servers, auth errors, duplicates, context window impact)
- Team MCP strategy (when to use each scope)
- MCP vs CLI decision framework

**Use When:** Adding/removing MCP servers, troubleshooting MCP issues, deciding team-wide vs personal MCP strategy

### PR Review Protocol

#### pr-review-protocol.md

**Purpose:** Structured protocol for AI-assisted PR reviews

**Features:**

- Review routing by file scope (spawn specialized reviewers)
- Present-before-posting workflow (user approval gate)
- GitHub Reviews API posting (inline comments, not PR-level)
- Severity classification (blocking vs suggestion)
- Finding verification protocol (verify before posting)
- Suggestive tone guidelines
- Wrong comment handling (delete, don't reply-correct)

**Use When:** Setting up AI-assisted PR reviews, training review agents, or defining review standards

### Scaffolding (`scaffolding/`)

A complete, anonymized example of a production `.claude/` directory that you can copy and customize.

**Includes:**

- Example project `CLAUDE.md` (navigation hub with agent roster, code standards, on-demand doc pointers)
- 2 example agents: infrastructure specialist + DevOps reviewer
- 3 example rules files: operational safety, terraform apply, PR review
- 3 example skills: deploy, verify-deploy, checkpoint
- 2 example docs: agent roster, architecture reference
- 1 example spec: CI/CD specification
- Example global `~/.claude/CLAUDE.md`
- Diagram showing how the pieces connect and when each file is loaded

**Use When:** Setting up `.claude/` from scratch — copy the entire directory and customize rather than starting from blank files. See `scaffolding/README.md` for the quick start guide.

### Project Templates (`project-templates/`)

Ready-to-customize documentation templates for your repository:

#### navigation-hub.md

**Purpose:** Central navigation and overview for `.claude/CLAUDE.md`

**Features:**

- Documentation organization and links
- Quick start guides for different roles
- Technology stack overview
- Architecture patterns summary
- Key principles and standards

**Use When:** Setting up `.claude/` directory structure

**Customization Needed:**

- Replace placeholder text with your project specifics
- Update file paths to match your structure
- Add/remove sections based on your needs

#### codebase-guide-template.md

**Purpose:** Comprehensive development guide

**Features:**

- Essential commands (build, test, run)
- Architecture overview and patterns
- Local development setup
- Common workflows
- Integration points
- Troubleshooting guides

**Use When:** Onboarding new developers, documenting architecture

**Customization Needed:**

- Replace `<service-name>`, `<module>` with actual names
- Update commands with project-specific syntax
- Document your actual architecture patterns
- Add project-specific workflows

#### github-actions-guide.md

**Purpose:** GitHub Actions workflow development standards

**Features:**

- Mandatory testing protocols (act testing, path validation)
- Project-specific patterns
- Change detection strategies
- Container build workflows
- Deployment patterns
- Security integration

**Use When:** Creating `.github/CLAUDE.md` for workflow guidance

**Customization Needed:**

- Replace `<AWS_ACCOUNT_ID>`, `<ECR_REGISTRY>` with your values
- Update service names and paths
- Customize matrix configurations
- Add project-specific workflows

#### devops-infrastructure-guide.md

**Purpose:** Infrastructure and Kubernetes documentation

**Features:**

- Terraform module organization
- Backend configuration patterns
- Workspace naming conventions
- Kubernetes & Helm standards
- Container best practices
- AWS/Cloud provider patterns
- Monitoring and troubleshooting

**Use When:** Creating `devops/CLAUDE.md` for infrastructure work

**Customization Needed:**

- Replace `<AWS_ACCOUNT_ID>`, `<org>`, `<domain>` with actual values
- Update Terraform module structure
- Customize Helm chart patterns
- Document your cloud resources

### Specifications (`specs/`)

#### ci-cd-specification.md

**Purpose:** RFC-style specification for CI/CD standards

**Features:**

- Iron rules (act testing, path validation, naming)
- GitHub Actions standards
- Terraform standards
- Docker standards
- Validation protocols
- Multi-language standards

**Use When:** Establishing team-wide CI/CD standards

**Customization:** Minimal - already generic and comprehensive

**Note:** Cursor IDE rules are maintained separately in `../cursor/mdc-rules/` directory. A Kubernetes/Helm rule has been added there.

## Context Window Optimization

Claude Code auto-loads all `CLAUDE.md` files into every conversation's context window. Bloated CLAUDE.md files directly reduce the space available for actual work, causing frequent conversation compactions.

### Principle: Auto-load rules, on-demand reference

- **Auto-loaded (`CLAUDE.md`)**: Only behavioral rules, constraints, and coding standards that Claude must follow in every conversation
- **On-demand (`.claude/docs/`)**: Reference material (build commands, architecture details, environment variables) that Claude reads only when needed

### What belongs in CLAUDE.md (auto-loaded)

- Code standards (type safety, naming conventions, patterns)
- Safety rules (dangerous commands, commit policies)
- Short pointers to on-demand docs: `For build commands, read .claude/docs/build-commands.md`

### What belongs in .claude/docs/ (on-demand)

- Build commands and local dev setup
- Architecture overviews and directory structure
- Technology stack details and version info
- Environment variable references
- AWS account details, profile mappings

### settings.local.json cleanup

The `settings.local.json` file accumulates one-off permission entries every time you approve a Bash command. Over time, this can grow to 30KB+ and is loaded into every conversation. Periodically replace specific entries with broad wildcards:

```json
{
  "permissions": {
    "allow": [
      "Bash(terraform:*)",
      "Bash(kubectl:*)",
      "Bash(helm:*)",
      "Bash(aws:*)",
      "Bash(git:*)"
    ]
  }
}
```

## Usage Guide

### Setting Up a New Repository

1. **Create `.claude/` directory structure:**

   ```bash
   mkdir -p .claude/specs .claude/docs
   ```

2. **Copy navigation hub (minimal, rules-only):**

   ```bash
   cp claude/project-templates/navigation-hub.md .claude/CLAUDE.md
   ```

3. **Copy reference docs (on-demand, not auto-loaded):**

   ```bash
   cp claude/project-templates/codebase-guide-template.md .claude/docs/codebase.md
   cp claude/project-templates/devops-infrastructure-guide.md .claude/docs/infrastructure.md
   ```

4. **Copy CI/CD spec (on-demand):**

   ```bash
   cp claude/specs/ci-cd-specification.md .claude/specs/
   ```

5. **Customize the files:**
   - Replace all `<placeholder>` values
   - Update service names, paths, and commands
   - Keep CLAUDE.md lean — move reference material to `docs/`

6. **Add directory-specific guides:**

   ```bash
   cp claude/project-templates/github-actions-guide.md .github/CLAUDE.md
   ```

7. **Set up selective git tracking:**

   ```bash
   # Create .claude/.gitignore
   echo "settings.local.json" > .claude/.gitignore
   echo "*.local.*" >> .claude/.gitignore

   # Update root .gitignore
   # Remove: .claude/
   # Add: .claude/settings.local.json
   #      .claude/*.local.*
   ```

**Note:** For Cursor IDE rules, see the existing `cursor/` directory structure with mdc-rules templates.

## Placeholder Reference

Common placeholders used in templates:

### Company/Organization

- `<COMPANY>` - Company name
- `<org>` - Organization name (lowercase)
- `<organization>` - Organization name (in URLs)
- `<repo-name>` - Repository name
- `<domain>` - Domain name (e.g., company.com)

### Cloud/Infrastructure

- `<AWS_ACCOUNT_ID>` - AWS account ID
- `<DEV_ACCOUNT_ID>` - Development account ID
- `<ECR_REGISTRY>` - ECR registry URL
- `<env>` - Environment (dev, staging, prod)
- `<tenant>` - Tenant identifier

### Services/Applications

- `<service-name>` - Generic service name
- `<service-api>` - API service name
- `<app-service>` - Application service
- `<module>` - Python module name
- `<app>` - TypeScript app name

### Databases/Queues

- `<app_db>` - Application database
- `<domain_db>` - Domain-specific database
- `<workflow_db>` - Workflow engine database
- `<insight-queue>` - Insight notification queue
- `<mesh-requests-queue>` - Agent mesh queue

### IAM/Security

- `<iam-role-name>` - IAM role name
- `<state-access-role>` - Terraform state access role
- `<bucket-name>` - S3 bucket name

## Best Practices

1. **Keep CLAUDE.md minimal** - Only rules and pointers; move reference material to `.claude/docs/`
2. **On-demand reference docs** - Build commands, architecture, tech stack go in `.claude/docs/` (not auto-loaded)
3. **Directory-specific guides** - Place guides close to the code they document
4. **Version control** - Commit all `.claude/` docs except `settings.local.json`
5. **Clean permissions regularly** - Replace one-off `settings.local.json` entries with broad wildcards
6. **Regular updates** - Review quarterly or when patterns change
7. **Team collaboration** - Submit PRs for documentation improvements

## Based On

These templates are extracted from a production monorepo with:

- 40+ microservices across Python, TypeScript, Java, and Go
- Event-driven architecture with AWS SQS
- Kubernetes deployment via Helm charts
- Terraform infrastructure (~40 modules)
- Comprehensive CI/CD via GitHub Actions
- 11 specialist agents (7 operational + 3 review + 1 utility)
- 10+ user-invocable skills (deploy, verify, inspect, scaffold, checkpoint, history mining)
- Auto-loaded operational rules from hundreds of real sessions
- Structured PR review protocol with specialized review agents

All company-specific and personally identifiable information has been sanitized.

## Contributing

Improvements welcome! If you find issues or have suggestions:

1. Test changes in a real project first
2. Ensure all placeholders are clearly marked
3. Keep templates generic and reusable
4. Update this README with any new patterns

---

**Last Updated**: 2026-03-06
**Template Version**: 3.0
