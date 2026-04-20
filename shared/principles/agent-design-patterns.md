# Agent Design Patterns

General principles for designing, structuring, and evolving AI coding agent systems. These patterns apply regardless of the specific tool (Claude Code, Cursor, Copilot Agents, custom agents).

## Core Concept: Specialist Agent Roster

Instead of one general-purpose agent handling all tasks, split work across specialist agents that each own a bounded domain. Benefits:

- **Deeper domain knowledge** per agent (more relevant context, fewer hallucinations)
- **Smaller context windows** (each agent loads only what it needs)
- **Clearer handoff points** (agents know when to defer)
- **Easier maintenance** (update one agent without affecting others)

## Agent Anatomy

Every effective specialist agent has these sections:

### 1. Identity & Scope

A clear, one-paragraph role statement defining:

- What the agent owns (its domain)
- What it does NOT own (explicit exclusions)
- The boundary conditions for when it should be invoked

### 2. Key References

Pointers to documentation the agent should read on-demand rather than carrying inline. This keeps the agent prompt lean while still giving access to deep reference material.

### 3. Domain Knowledge

Structured tables, inventories, and reference data specific to the agent's domain. Prefer tables over prose — they're denser and easier to scan.

Good domain knowledge sections:

- **Inventory tables** — What the agent manages (modules, services, resources)
- **Pattern tables** — Naming conventions, workspace patterns, configuration schemas
- **Comparison tables** — Variant behavior (e.g., single-tenant vs multi-tenant, dev vs prod)

### 4. Failure Triage Table

A structured `Symptom → Root Cause → Fix` table covering the most common failures in the agent's domain. This is often the highest-value section — it prevents the agent from reinventing diagnosis logic on every invocation.

Design principles for triage tables:

- **20-30 rows** is the sweet spot (covers ~90% of cases without bloat)
- **Symptom column** should match what the user actually sees (error messages, observable behavior)
- **Root cause** should be specific enough to act on
- **Fix column** should be a concrete action, not "investigate further"
- Include cross-domain deferrals: "Defer to **{sibling-agent}**"

### 5. Behavioral Rules

Numbered rules the agent MUST follow. Keep to 8-15 rules. Categories:

- **Safety rules** — What the agent must NEVER do without confirmation
- **Process rules** — What to read/check before acting
- **Quality rules** — Standards to maintain (formatting, validation, reporting)
- **Credential rules** — How to handle expired auth, missing access

### 6. Decision Checkpoints

Operations that require explicit user approval before proceeding. These are the "measure twice, cut once" moments — destructive operations, state changes, or actions affecting shared infrastructure.

### 7. Scope Constraint

Explicit boundary on what files/directories the agent may modify. Prevents scope creep where agents "helpfully" refactor adjacent code.

### 8. Sibling Agent Deferral Table

A `Situation → Defer To` table mapping cross-domain scenarios to the correct specialist agent. Every agent should know its neighbors.

### 9. Verification Commands

Ready-to-run commands for validating the agent's work. The agent should be able to verify its own changes.

## When to Split an Agent

A single agent should be split into two when:

### Quantitative Signals

- **>70% of sessions** concentrate in one sub-domain — the minority use case gets underserved
- **Repeated corrections** in one area suggest the agent's context is too broad to maintain accuracy
- **Different error patterns** — the sub-domains have distinct failure modes requiring different triage tables
- **Agent prompt exceeds ~350 lines** and covers meaningfully different domains

### Structural Signals

- **Distinct dependency chains** — sub-domains have their own sequential workflows
- **Different naming/convention schemes** — sub-domains use different patterns (6+ distinct workspace naming patterns is a strong signal)
- **Different CI/CD integration points** — sub-domains interact with different pipelines
- **Different provider/tool ecosystems** — one sub-domain uses database providers while another uses cloud providers
- **Different scope levels** — one sub-domain is cluster-wide, another is per-tenant

### Anti-Patterns (Don't Split When)

- The sub-domains share most of their knowledge and differ only in target directory
- Splitting would require duplicating >50% of the content in both agents
- The split would create agents with <100 lines of unique content
- Users frequently need both domains in a single session

## How to Split an Agent

### Execution Order

1. **Create the new agent** — no dependencies, standalone creation
2. **Rewrite the original** — remove migrated content, add deferral to new agent. Do this AFTER step 1 to avoid content loss.
3. **Update all sibling agents** — replace single deferral row with two rows. These edits are independent and can be done in parallel.
4. **Update central roster** — add the new agent to any agent inventory files
5. **Run verification checklist** — automated checks to catch broken references

### Verification Checklist

After any agent split or restructuring:

1. **File count** — expected number of agent files exists
2. **Cross-reference completeness** — every agent references every other agent it might defer to
3. **No orphaned deferrals** — no agent points to a name that doesn't exist
4. **Content separation** — the original agent no longer contains domain-specific content that was migrated
5. **New agent contains required sections** — inventory, triage table, verification commands, behavioral rules
6. **Central roster updated** — agent count and descriptions are current
7. **End-to-end read** — read all agents to confirm no broken cross-references

## Cross-Agent Deferral Patterns

### The Sibling Table

Every agent maintains a table mapping situations to the correct specialist:

```
| Situation                     | Defer To              |
|-------------------------------|-----------------------|
| Database provisioning errors  | **database-expert**   |
| Secret sync failures          | **secrets-expert**    |
| Pipeline CI failures          | **pipeline-expert**   |
```

### Deferral Rules

- **Be specific about the boundary** — "TF plan/apply on deployment modules" is better than "Terraform issues"
- **Split rows when agents split** — if `infra-expert` becomes `infra-expert` + `deploy-expert`, replace one row with two in every sibling
- **Include the direction** — the deferral should tell the sibling agent to handle it, not just mention it exists
- **Central roster as source of truth** — maintain a single roster file that all agents reference for the canonical list

### Structured Handoff Format

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

### The ESO Chain Pattern

When agents form a sequential chain (A's output feeds B's input), document this explicitly. Example: "After applying infrastructure changes, verify the downstream sync or defer to the next agent in the chain."

## Failure Triage Table Design

### Structure

```
| Symptom | Root Cause | Fix |
|---------|-----------|-----|
| [Observable error/behavior] | [Specific cause] | [Concrete action] |
```

### Design Principles

- **Match user's vocabulary** — the symptom column should use the actual error messages or descriptions users report
- **One fix per row** — if a symptom has multiple causes, create multiple rows
- **Include cross-domain deferrals** — "Defer to **{agent}**" is a valid fix
- **Order by frequency** — most common issues first
- **Include "STOP" items** — operations that should halt and wait for human confirmation
- **Cover the 80/20** — 20-30 rows typically cover 80% of real-world failures

## Agent Prompt Size Guidelines

| Agent Complexity | Target Lines | Sections |
|-----------------|-------------|----------|
| Simple (single tool/area) | 80-150 | Identity, knowledge, rules, siblings |
| Standard (bounded domain) | 150-250 | + triage table, verification commands, checkpoints |
| Complex (multi-tool domain) | 250-400 | + provider-specific sections, comparison tables, CI/CD integration |

Above 400 lines, strongly consider splitting. Below 80 lines, the agent may not carry enough context to be useful.

## Context Window Optimization

### What to Include Inline

- Behavioral rules the agent must always follow
- Inventory tables it frequently looks up
- The triage table (highest-value per token)
- Sibling deferral table

### What to Reference On-Demand

- Detailed READMEs for specific modules
- Full CI/CD workflow specifications
- Architecture deep-dives
- Historical learnings and gotchas

### Pre-Compaction Memory Flush

When an agent's context window approaches capacity, proactively persist durable findings before compaction discards them. Add an instruction like:

> "When your context is large and you have accumulated significant findings, write a summary to your memory file before proceeding with additional work."

This prevents the loss of diagnostic context, configuration discoveries, or partial solutions during long sessions.

### Heartbeat / Periodic Check Pattern

For operational agents (monitoring, drift detection, health checks), define periodic check routines:

```markdown
## Periodic Checks (when invoked for routine review)
- [ ] Check all resource sync status across namespaces
- [ ] Verify no access errors in controller logs
- [ ] Compare source-of-truth counts vs deployed counts for drift
```

These turn agents from reactive (invoked only when something breaks) to proactive (invoked for routine health sweeps).

### The "Key References" Pattern

Instead of embedding 500 lines of documentation, include a 5-line section:

```
Always read these files when you need detailed information:
- `path/to/module-index.md` — Full inventory with lookup table
- `path/to/standards.md` — Coding standards and safety rules
- `path/to/ci-cd-guide.md` — Pipeline patterns and composite actions
```

This gives the agent access to deep knowledge without consuming context window on every invocation.

## Memory / Learning Protocol

Effective agents accumulate knowledge across sessions:

1. **Propose** — Agent identifies a pattern, correction, or gotcha worth remembering
2. **Confirm** — User approves saving it (prevents noise accumulation)
3. **Persist** — Write to a shared learnings file that all agents can read

Categories that work well: naming corrections, configuration gotchas, dependency ordering, provider quirks, common misconfigurations.

## Evolution Patterns

### Adding a New Agent

1. Identify the domain boundary
2. Check existing agents for overlap — if >30% content overlap, consider extending instead
3. Create with all required sections
4. Add deferral rows to all relevant siblings
5. Update central roster
6. Verify cross-references

### Retiring an Agent

1. Verify the domain is absorbed by another agent or no longer needed
2. Remove deferral rows from all siblings
3. Update central roster
4. Archive (don't delete) the agent file for reference

### Merging Agents

The inverse of splitting. Consider when:

- Two agents are <100 lines each
- Users frequently invoke both in the same session
- The combined agent would be <300 lines
- The domains share >70% of their knowledge
