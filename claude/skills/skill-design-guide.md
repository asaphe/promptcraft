# Claude Code Skill Design Guide

How to design, structure, and maintain Claude Code skills — user-invocable interactive workflows triggered via `/command`.

## What Skills Are

Skills are interactive workflows that users invoke with slash commands (e.g., `/deploy`, `/checkpoint`, `/check-secret`). Each skill is a markdown file with YAML frontmatter that defines:

- A name (the slash command)
- Which tools the skill can use
- A structured system prompt with steps, safety rules, and output formats

Skills live in `.claude/skills/<skill-name>/SKILL.md` and are discovered automatically by Claude Code.

## Skills vs Agents

| Dimension | Skill | Agent |
| --------- | ----- | ----- |
| **Invocation** | User types `/command` | Orchestrator spawns via Task tool |
| **Context** | Runs in the main conversation (shares full history) | Runs as subprocess (fresh context) |
| **Scope** | Single focused workflow | Broad domain expertise |
| **Duration** | Usually one pass through defined steps | May run many turns |
| **State** | Shares parent session state | Isolated subprocess |

**Use a skill when:** The workflow is user-initiated, has defined steps, and benefits from conversation context (e.g., deploying an app, running a health check, scaffolding a module).

**Use an agent when:** The task requires deep domain expertise, independent investigation, or isolation from the main context (e.g., Terraform troubleshooting, Kubernetes debugging, PR review).

## YAML Frontmatter Specification

```yaml
---
name: my-skill                    # kebab-case, becomes /my-skill command
description: >-                   # Shown in skill listing and help
  One-line description of what this skill does.
  Usage - /my-skill [arguments]
user-invocable: true              # Must be true for slash command access
allowed-tools: Bash(kubectl *), Bash(helm *), Read, Grep, Glob, AskUserQuestion
argument-hint: "[application] [environment]"  # Placeholder shown to user
---
```

### Field Details

#### `name`

- **Format:** kebab-case (e.g., `deploy`, `check-secret`, `new-tf-module`)
- **Becomes** the `/name` slash command
- **Keep short** — users type this frequently

#### `description`

- First sentence: what the skill does
- Second sentence: usage pattern with argument hint
- Wrap with `>-` for multi-line YAML

#### `user-invocable`

Must be `true` for skills meant to be invoked via slash commands. Set to `false` for skills loaded by agents via the `skills` frontmatter field.

#### `allowed-tools`

Grant the minimum tools needed. Common patterns:

| Skill Type | Tools |
| ---------- | ----- |
| Read-only inspection | `Bash(kubectl *), Bash(aws *), Read, Grep, Glob, AskUserQuestion` |
| Deployment trigger | `Bash(gh *), AskUserQuestion, Read, Grep, Glob` |
| Scaffolding/creation | `Bash(*), Read, Write, Edit, Glob, Grep, AskUserQuestion` |
| Investigation only | `Read, Grep, Glob, AskUserQuestion` |

**Bash tool scoping:** Use `Bash(command *)` to restrict shell access to specific commands. `Bash(kubectl *)` allows any kubectl command but blocks other shell commands. Use `Bash(*)` only when the skill genuinely needs unrestricted shell access.

**Cover all execution paths, not just the happy path:** Audit every conditional branch in the skill body — including no-input fallbacks, optional modes, and error recovery steps — and ensure each tool they reference is listed. A tool missing from `allowed-tools` silently fails at runtime with no warning at authoring time.

**MCP tool naming is exact:** MCP tools follow the `mcp__{server-name}__{tool-name}` pattern (double underscores, hyphens in server name become underscores). Never abbreviate or guess — verify against the MCP server's actual tool list. `my_server_get_task` is wrong; `mcp__my-server__get_task` is correct.

#### `argument-hint`

Shown to the user as a placeholder when they type the command. Use brackets for optional args:

```yaml
argument-hint: "[application-name]"
argument-hint: "[application] [deployment-name]"
argument-hint: "[--since YYYY-MM-DD] [--category category]"
```

## System Prompt Structure

The markdown body after frontmatter becomes the skill's prompt. Follow this structure:

### 1. Title

```markdown
# Action Description

Brief one-line description of what this skill accomplishes.
```

### 2. Steps (Numbered Sections)

Each major phase of the workflow gets a numbered section:

```markdown
## Steps

### 1. Determine parameters

If `$ARGUMENTS` is provided, parse application and environment from it.
Otherwise, ask the user to select.

### 2. Execute operation

Run the actual commands...

### 3. Present results

Format and display the output...
```

### 3. Parameter Resolution Pattern

Skills should resolve parameters from three sources, in priority order:

```markdown
### 1. Determine parameters

If `$ARGUMENTS` is provided, use it as the application name. Otherwise, ask the user to select.

**Valid applications:**
<list of valid values>

Ask the user (if not already specified):

1. **Environment**: staging or production
2. **Target name**: <list based on environment>
3. **Additional option**: <description>
```

This pattern (args first, then interactive) makes skills fast when you know what you want and discoverable when you don't.

### 4. Confirmation Gates

Before irreversible actions, present a summary and require explicit confirmation:

```markdown
### 3. Confirm with user

Before triggering, show a summary:

\```
Deploying:
  Application:  {application}
  Environment:  {environment}
  Target:       {target}
  Version:      {version}
\```

Ask for explicit confirmation before proceeding.
```

### 5. Output Formatting

Present results in structured, scannable formats:

```markdown
### 4. Present summary

Format results as a status dashboard:

\```
Health Check: {application} in {environment}
===============================================

  Component A:  GREEN  -- All instances healthy
  Component B:  YELLOW -- 2 warnings (retry detected)
  Component C:  GREEN  -- No issues

Overall: HEALTHY (1 advisory)
\```
```

### 6. Safety Section

Every skill ends with explicit safety boundaries:

```markdown
## Safety

- NEVER execute without explicit user confirmation
- NEVER default to production — always ask
- This is a read-only skill — no state changes
- All commands are observational (get, list, logs, describe)
```

## Skill Design Patterns

### Parameterized Workflows

Skills that accept arguments and resolve them interactively:

```markdown
### 1. Determine parameters

If `$ARGUMENTS` is provided, use it as the target. Otherwise, ask:

1. **Category**: infrastructure, application, data
2. **Name**: kebab-case identifier
3. **Options**: Select applicable features
```

### Confirmation Gates Before Irreversible Actions

Any skill that modifies state must confirm before executing:

```markdown
### 3. Confirm with user

Before executing, show exactly what will happen:
- Resources to be created/modified/deleted
- Target environment and scope
- Estimated impact

Ask for explicit confirmation before proceeding.
```

### Multi-Step Verification (Gather -> Confirm -> Execute -> Monitor)

Complex workflows follow a four-phase pattern:

1. **Gather** — Collect parameters, resolve defaults, validate inputs
2. **Confirm** — Present a summary of what will happen
3. **Execute** — Run the actual operation
4. **Monitor** — Watch for completion, report results

### Read-Only vs Write Skills

**Read-only skills** (inspection, drift detection, health checks):

- Grant only read tools: `Bash(kubectl *), Read, Grep, Glob`
- Safety section states "read-only — no state changes"
- No confirmation gates needed (nothing destructive)

**Write skills** (deploy, scaffold, create):

- Grant write tools: `Bash(*), Write, Edit`
- Confirmation gates before every destructive step
- Safety section lists explicit prohibitions

### Dashboard Output

Skills that report status should use a consistent dashboard format with clear severity indicators and actionable findings.

## Common Skill Archetypes

### Deploy Skill

Triggers a deployment workflow. Parameters: application, environment, target, version.

Key patterns:

- Resolve version from registry (never silently default to "latest")
- Confirm before triggering
- Monitor workflow execution after triggering
- Share run URL for async tracking

### Verify/Health-Check Skill

Post-action verification. Parameters: application, target.

Key patterns:

- Run multiple independent checks in parallel
- Classify each result (healthy/warning/critical)
- Present consolidated dashboard
- Offer to dig deeper into problem areas

### Inspect/Drift-Detect Skill

Compare expected vs actual state. Parameters: application, target.

Key patterns:

- Fetch state from multiple sources (config file, cloud API, running system)
- Compare and identify discrepancies
- Classify drift as intentional vs unintentional
- Suggest remediation for each finding

### Scaffold Skill

Create new resources from templates. Parameters: category, name, options.

Key patterns:

- Discover existing conventions (naming, structure, versions)
- Create all standard files
- Run formatting/validation
- Report what was created and suggest next steps

### Checkpoint Skill

Capture session state for handoff between sessions.

Key patterns:

- Gather git state, uncommitted changes, recent commits
- Summarize work done and remaining from conversation context
- Format as structured handoff document
- Offer to save learnings as rules

### Session History Mining Skill

Scan past conversations for uncodified patterns and repeated corrections.

Key patterns:

- Parse conversation history files
- Detect correction signals ("no", "wrong", "stop")
- Identify recurring topics and long recovery sequences
- Present candidate rules for interactive approval

## Sizing Guidelines

| Skill Type | Lines | Notes |
| ---------- | ----- | ----- |
| Simple trigger | 40-70 | Parameter resolution, confirm, execute |
| Inspection/verification | 70-120 | Multiple checks, dashboard output |
| Complex workflow | 100-160 | Multi-phase, conditional logic, monitoring |

**Above 160 lines:** Consider splitting into multiple skills or extracting reference material into separate files.

## Common Mistakes

### No Parameter Resolution

**Wrong:** Skill assumes all parameters are always provided as arguments.
**Right:** Parse `$ARGUMENTS` first, fall back to interactive prompts.

### No Confirmation Gate

**Wrong:** Skill deploys/creates/deletes immediately upon invocation.
**Right:** Present summary and require explicit "yes" before any state change.

### Overly Broad Tool Grants

**Wrong:** `allowed-tools: Bash(*)` for a read-only inspection skill.
**Right:** `allowed-tools: Bash(kubectl *), Bash(aws *), Read, Grep, Glob` — minimum necessary.

### No Safety Section

**Wrong:** Skill ends after the last step with no explicit safety boundaries.
**Right:** Every skill has a `## Safety` section listing what it will and won't do.

### Embedding Domain Knowledge

**Wrong:** 50 lines of configuration reference inline in the skill.
**Right:** Point to a doc file: "Read `.claude/docs/<reference>.md` for the full configuration table."
