# Claude Code Agent Design Guide

How to design, structure, and maintain Claude Code subagents (the `.md` files in `.claude/agents/`).

## How Claude Code Agents Work

Claude Code discovers agent files from `.claude/agents/*.md`. Each file defines a specialist that can be invoked via the Task tool with `subagent_type` matching the agent's `name` field. The agent receives:

- The YAML frontmatter as configuration (model, tools, memory)
- The markdown body as its system prompt
- Access to the tools listed in the frontmatter

Agents run as subprocesses with their own context window. They do NOT share conversation history with the parent — they get a fresh context with only their system prompt and the task description.

## YAML Frontmatter Specification

```yaml
---
name: my-agent-name           # kebab-case, matches subagent_type in Task tool
description: >-               # Multi-line description shown in tool selection
  One-paragraph description of what this agent does.
  Include when to use it and primary use cases.
tools: Read, Edit, Write, Glob, Grep, Bash   # Comma-separated tool list
model: opus                   # opus | sonnet | haiku
memory: project               # project | local | none
---
```

### Field Details

#### `name`

- **Format:** kebab-case (e.g., `terraform-expert`, `k8s-troubleshooter`)
- **Must match** the `subagent_type` parameter used in Task tool calls
- **Convention:** `{domain}-expert` for specialists, `{domain}-{role}` for specific roles

#### `description`

- **First sentence:** What the agent IS (its role)
- **Second sentence:** When to USE it (trigger conditions)
- **Include keywords** that help the orchestrator match tasks to agents
- **Wrap with `>-`** for multi-line YAML strings (folds to single line, strips trailing newline)

#### `tools`

Available tools to grant:

| Tool Set | Use Case |
|----------|----------|
| `Read, Glob, Grep, Bash` | Read-only investigation agents |
| `Read, Edit, Write, Glob, Grep, Bash` | Agents that modify code |
| `Read, Glob, Grep` | Pure research agents (no shell access) |

Grant the minimum tools needed. Investigation-only agents don't need `Edit` or `Write`.

#### `model`

| Model | When to Use |
|-------|-------------|
| `opus` | Complex reasoning, code generation, multi-step planning, architecture decisions |
| `sonnet` | Routine investigation, log analysis, status checks, straightforward edits |
| `haiku` | Simple lookups, formatting, quick classification |

**Rule of thumb:** If the agent writes code or makes architectural decisions → `opus`. If it mostly reads and reports → `sonnet`.

#### `memory`

| Value | Behavior |
|-------|----------|
| `project` | Agent can read/write project-scoped memory (`.claude/docs/learnings.md`) |
| `local` | Agent memory is session-local only |
| `none` | No memory access |

Most specialist agents should use `project` to accumulate learnings.

#### `maxTurns`

Limits the agent's execution to N agentic turns (API round-trips). Prevents runaway execution.

| Agent Type | Recommended maxTurns |
|-----------|---------------------|
| Complex implementer (TF plan/apply, CI/CD authoring) | 40-60 |
| Diagnostic/investigator | 25-35 |
| Simple lookup/formatter | 10-15 |

#### `hooks`

Lifecycle hooks that fire during agent execution:

| Hook | When It Fires | Use Case |
|------|--------------|----------|
| `PreToolUse` | Before any tool call | Validation, logging, permission checks |
| `PostToolUse` | After any tool call | Result verification, state tracking |
| `Stop` | When agent completes | Structured handoff output, cleanup |

Example: A `Stop` hook can output the next recommended agent invocation, creating explicit handoff chains.

#### `skills`

Preloads specific skills into the agent's context. Enables progressive disclosure — skills are loaded on-demand rather than embedding all knowledge in the system prompt.

#### `isolation`

Set to `worktree` to run the agent in a separate git worktree. Useful for agents that modify code, preventing conflicts with the main session's working tree.

#### `background`

Set to `true` to run the agent asynchronously. The parent session continues while the agent works. Useful for diagnostic agents that produce reports.

## System Prompt Structure

The markdown body after the frontmatter becomes the agent's system prompt. Recommended structure:

### 1. Role Paragraph (2-3 lines)

```markdown
You are a [domain] expert for [project description]. You own [specific responsibilities]
and specialize in [key capabilities].
```

### 2. Key References Section

```markdown
## Key References

Always read these files when you need detailed information:

- `path/to/index.md` — Module inventory and lookup table
- `path/to/standards.md` — Coding standards and safety rules
```

**Why this matters:** Agents have limited context windows. Instead of embedding all knowledge inline, point to files the agent can `Read` on demand. This is the single most impactful optimization for agent quality.

### 3. Domain Knowledge

Tables are the most token-efficient format for structured knowledge:

```markdown
## Module Inventory

| Module | Purpose | Config Pattern |
|--------|---------|---------------|
| `module-a` | Does X | `{env}_{name}` |
| `module-b` | Does Y | `{env}_{name}_{region}` |
```

Include:

- **Inventory tables** — what the agent manages
- **Pattern tables** — naming conventions, configuration schemas
- **Comparison tables** — variant behavior (dev vs prod, type A vs type B)

### 4. Failure Triage Table

```markdown
## Failure Triage Table

| Symptom | Root Cause | Fix |
|---------|-----------|-----|
| `Error: state lock` | S3 lock not released | `terraform force-unlock {id}` |
| Connection refused | VPN not connected | Connect to VPN first |
| Wrong namespace in output | Wrong workspace | Switch workspace |
```

This is typically the highest-value section. 20-30 rows covering common failures prevents the agent from spending tokens on diagnosis.

### 5. Verification Commands

```markdown
## Verification Commands

\```bash
# Check current state
command-to-verify-state

# Validate output
command-to-validate-output
\```
```

Give the agent ready-to-run commands for validating its own work.

### 6. Behavioral Rules

```markdown
## Your Behavior

1. **Read reference docs first** when you need detailed information.
2. **NEVER apply changes without presenting a plan** and getting confirmation.
3. **ALWAYS verify the target** before any operation.
4. **STOP if unexpected changes appear** — report, do not proceed.
5. **Report all findings** — unexpected issues are always relevant.
6. If credentials are expired, renew them automatically and continue.
```

Keep to 8-15 rules. Group by category: safety, process, quality, credentials.

### Directive Language (Claude 4.6+)

Claude 4.6 is more responsive to system prompts than earlier models. Adjust directive language by category:

**Remove entirely:**

- Anti-laziness prompts: "be thorough", "think carefully", "do not be lazy"
- These amplify already-proactive behavior and cause runaway thinking

**Soften (add motivation instead of emphasis):**

- Tool-triggering: Replace "CRITICAL: You MUST use this tool" with "Use this tool when..."
- Process steps: Replace "ALWAYS verify X" with "Verify X because [consequence]"
- The *why* helps Claude generalize correctly; bare emphasis does not

**Keep strong (safety-critical):**

- Irreversible operations: "NEVER apply without presenting a plan" — these prevent destructive actions
- Production safety: "NEVER deploy to production without confirmation"
- Anthropic's own Claude Code prompt uses NEVER for destructive git commands

**The principle:** When everything is CRITICAL, nothing is. Reserve strong directives for genuinely irreversible or destructive actions. Use motivated normal language for everything else.

### Structured Handoff Protocol

When deferring to a sibling agent, provide structured context (not just "invoke X"):

```markdown
## Handoff to {target-agent}
- **Reason:** {why this crosses domain boundaries}
- **Context gathered:** {relevant findings from this session}
- **Specific question:** {focused ask for the target agent}
- **Files examined:** {list of relevant paths}
- **Current state:** {what's been changed, what hasn't}
```

This preserves diagnostic context across agent boundaries, preventing the target agent from re-doing investigation work.

### 7. Decision Checkpoints

```markdown
## Decision Checkpoints (STOP and confirm before proceeding)

- **Resource creation** — Present the proposed configuration and wait.
- **State modification** — Show what will change, confirm before running.
- **File creation outside target** — State which files and why, wait for approval.
```

### 8. Scope Constraint

```markdown
## Scope Constraint

Only modify files within `path/to/owned-directory/`. If changes outside
this directory are needed, explicitly state what and why before proceeding.
```

### 9. Sibling Agents Table

```markdown
## Sibling Agents

| Situation | Defer To |
|-----------|----------|
| Database provisioning issues | **database-expert** |
| Secret management issues | **secrets-expert** |
| Pod runtime failures | **k8s-troubleshooter** |
| Pipeline/CI failures | **pipeline-expert** |
```

**Every agent must list its siblings.** When an agent is added or split, update all sibling tables.

### 10. Memory Usage Protocol

```markdown
## Memory Usage Protocol

When you discover something noteworthy (a pattern, a correction, a gotcha):

1. Propose it: `LEARNING: [category] [description] / CONTEXT: [what happened] / SCOPE: project|local`
2. Only save after the user confirms ("save that" or similar)
3. Write project-scoped learnings to `.claude/docs/learnings.md`
```

## Agent Roster File

Maintain a central roster that all agents reference:

```markdown
# Agent Roster

| Agent | Domain | Defer To It When |
|-------|--------|-----------------|
| **infra-expert** | VPC, DNS, cluster management | Infrastructure plan/apply, state ops |
| **deploy-expert** | Deployment modules, app config | Deployment plan/apply, workspace patterns |
| **secrets-expert** | Secret sync chain, IAM policies | Secret format, drift, sync errors |
```

Update this file whenever agents are added, removed, split, or merged.

## Central CLAUDE.md Integration

The project's root `.claude/CLAUDE.md` should list all agents:

```markdown
## Specialized Agents

Seven specialist agents handle domain-specific tasks.
See `.claude/docs/agent-roster.md` for full boundaries and deferral rules.

| Agent | When to Use |
|-------|-------------|
| **agent-a** | Brief description |
| **agent-b** | Brief description |
```

Keep descriptions in CLAUDE.md very brief (one line each) — the full details live in the agent files themselves.

## Sizing Guidelines

| Agent Type | Lines | Notes |
|-----------|-------|-------|
| Investigation-only | 80-150 | Diagnostic flow, triage table, verification commands |
| Standard specialist | 150-250 | + behavioral rules, scope constraint, decision checkpoints |
| Complex specialist | 250-400 | + provider-specific sections, CI/CD integration, comparison tables |

**Above 400 lines:** Split the agent. The context window cost outweighs the benefit.
**Below 80 lines:** Consider merging with a related agent — too little context to be useful.

## Progressive Disclosure via Skills

Instead of embedding all domain knowledge in the agent's system prompt (consuming context on every invocation), factor reference material into skill files:

**What to keep in the agent prompt:**

- Behavioral rules (8-15 rules)
- Sibling deferral table
- Scope constraint
- Key references (file paths to read on-demand)

**What to extract into skills:**

- Failure triage tables (20-30 rows x 3 columns = significant tokens)
- Domain knowledge inventories
- Verification command libraries
- CI/CD integration details

**How it works:** The `skills` frontmatter field loads skill names + descriptions (~24 tokens each) at startup. The full skill body is loaded only when the agent determines it's relevant. This can reduce baseline prompt size by 40-60%.

**Trade-off:** Skills add a retrieval step. For knowledge the agent needs on >80% of invocations, inline is better. For knowledge needed <50% of the time, skills win.

## Common Mistakes

### Over-Embedding Reference Material

**Wrong:** Inline 200 lines of module documentation in the agent prompt.
**Right:** Include a 5-line "Key References" section pointing to docs the agent can `Read`.

### Missing Sibling Deferrals

**Wrong:** Agent has no sibling table, tries to handle everything.
**Right:** Explicit deferral table with specific situations mapped to specific agents.

### Vague Behavioral Rules

**Wrong:** "Be careful with infrastructure changes."
**Right:** "NEVER apply without presenting a plan first and getting explicit user confirmation."

### No Failure Triage Table

**Wrong:** Agent must reason from scratch about every error.
**Right:** 20-30 row triage table covering common failures with concrete fixes.

### Scope Creep

**Wrong:** Agent modifies files outside its domain "to be helpful."
**Right:** Explicit scope constraint: "Only modify files within `path/to/domain/`."

### Model Over-Provisioning

**Wrong:** Every agent uses `opus`.
**Right:** Investigation agents use `sonnet`, code-writing agents use `opus`.
