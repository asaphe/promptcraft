# Review Agent Trio Pattern

How to design a set of specialized review agents that divide PR review responsibilities by domain, producing higher-quality findings than a single generalist reviewer.

## The Problem

A single "reviewer" agent that handles all file types produces shallow findings. It lacks the domain-specific knowledge to catch nuanced issues in Terraform, secrets configuration, or agent definitions. It also wastes context window by loading all domain knowledge even when only reviewing one file type.

## The Pattern

Split review into **three (or more) specialized agents**, each focused on a domain with deep triage knowledge:

```text
PR Review Request
       │
       ├─── devops-reviewer      (Terraform, Actions, Dockerfiles, shell, Helm)
       ├─── secrets-reviewer     (secret tfvars, ExternalSecret, naming convention)
       └─── config-reviewer      (agent definitions, skills, commands, CLAUDE.md)
```

The orchestrator (main Claude session or a `/pr-review` skill) examines the changed files, spawns only the relevant reviewer(s), collects findings, and presents them to the user before posting.

## Why Three?

The split follows **correction frequency domains** — areas where the most mistakes happen in practice:

| Domain | Why It's Separate | Typical Findings |
|--------|------------------|------------------|
| Infrastructure/DevOps | Broad scope, many file types, security implications | Missing `|| true` in pipelines, wrong workspace, unvalidated plans |
| Secrets/Config | Highest-frequency correction domain, subtle format mismatches | Wrong secret path, missing tenant, template syntax mismatch |
| Agent/Tool Config | Self-referential (agents reviewing agent changes), unique validation | Missing sibling deferral, stale roster, invalid frontmatter |

Your domains will differ. The principle is: **split along the boundaries where mistakes cluster**.

## Agent Design

### Common Properties

All review agents share:

```yaml
---
tools: Read, Glob, Grep, Bash(gh *), Bash(git *)
model: sonnet       # Read-only analysis doesn't need opus
maxTurns: 25
---
```

Key design choices:
- **Read-only tools** — reviewers should never modify code
- **`Bash(gh *)`** — needed to fetch PR diffs, comments, review threads
- **Sonnet model** — sufficient for pattern matching and checklist validation; saves cost vs opus
- **No `Edit` or `Write`** — prevents accidental modifications (add `Write` only if the reviewer posts findings directly)

### DevOps Reviewer Example

```yaml
---
name: devops-reviewer
description: >-
  Read-only reviewer for DevOps file changes — Terraform, GitHub Actions,
  Dockerfiles, shell scripts, and Helm charts. Use for PR review of
  infrastructure and CI/CD changes.
tools: Read, Glob, Grep, Bash(gh *), Bash(git *), Bash(shellcheck *), Bash(hadolint *), Bash(terraform *)
model: sonnet
maxTurns: 25
---
```

System prompt includes:
- **File-type checklist** — what to verify for each file type (HCL, YAML, Dockerfile, .sh)
- **Severity classification** — blocking vs suggestion vs nitpick
- **Common anti-patterns table** — 20-30 rows of known bad patterns with examples
- **Verification commands** — `shellcheck`, `hadolint`, `terraform validate`

### Secrets Reviewer Example

```yaml
---
name: secrets-config-reviewer
description: >-
  Read-only reviewer for secrets and multi-tenant configuration changes —
  tfvars secret blocks, helm template secret refs, ExternalSecret configs,
  and secret naming convention compliance.
tools: Read, Glob, Grep, Bash(gh *), Bash(git *), Bash(jq *)
model: sonnet
maxTurns: 25
---
```

System prompt includes:
- **Secret naming convention** — expected path formats by scope (global, per-tenant, per-app)
- **Format validation table** — which apps expect which JSON structure
- **Template syntax rules** — `.tfvars` uses `<TOKEN>`, `.yaml.tftpl` uses `${variable}`
- **Cross-environment consistency checks** — staging and prod templates should match structurally

### Config Reviewer Example

```yaml
---
name: agent-config-reviewer
description: >-
  Read-only reviewer for .claude/ configuration changes — agent, skill,
  and command frontmatter validation, section completeness, cross-config
  consistency, and roster sync.
tools: Read, Glob, Grep, Bash(gh *)
model: sonnet
maxTurns: 25
---
```

System prompt includes:
- **Frontmatter schema** — required fields for agents, skills, commands
- **Section checklist** — expected sections per agent (role, references, triage table, rules, scope, siblings)
- **Roster sync validation** — new agent ↔ roster ↔ CLAUDE.md consistency
- **Hook validation** — script paths exist, are executable, have valid timeout/async/matcher fields

## Orchestration

### Via Skill (`/pr-review`)

The most ergonomic approach is a skill that:

1. Fetches the PR's changed files
2. Classifies files by domain
3. Spawns relevant reviewers in parallel
4. Collects and deduplicates findings
5. Presents findings to the user for approval
6. Posts approved findings as inline PR comments

```markdown
## File Routing

| File Pattern | Reviewer |
|-------------|----------|
| `devops/terraform/**`, `.github/**`, `**/Dockerfile*`, `**/*.sh` | devops-reviewer |
| `**/vars/*secrets*`, `**/*external-secret*`, `**/secret-*` | secrets-config-reviewer |
| `.claude/**` | agent-config-reviewer |
| Other | Skip or use general-purpose review |
```

### Via Main Session

For smaller PRs, the orchestrator can spawn reviewers directly:

```
User: review PR #1234
Claude: [reads changed files, spawns devops-reviewer for the .tf changes]
```

## Finding Quality Protocol

The review trio pattern only works if findings are accurate. Wrong findings destroy credibility faster than missing findings.

### Self-Verification Rule

Every reviewer agent must include this behavioral rule:

```markdown
Before presenting any finding:
1. Re-check it against the actual code (not your summary of the code)
2. Verify against official docs or primary sources if citing a standard
3. If uncertain, downgrade severity or drop the finding entirely
```

### Present-Before-Posting

Never post findings directly to GitHub without user approval:

```text
Reviewer → Findings list → User reviews → Approved findings → GitHub comments
```

This prevents embarrassing wrong comments that require cleanup.

### Severity Classification

| Level | Meaning | Action |
|-------|---------|--------|
| **Blocking** | Will cause failures, security issues, or data loss | Must fix before merge |
| **Suggestion** | Improvement opportunity, best practice deviation | Author decides |
| **Nitpick** | Style, naming, minor readability | Low priority |

Use suggestive language: "Consider..." / "Would it make sense to..." — not "You must..." or "This is wrong."

## Scaling the Pattern

### Adding a New Reviewer

When a new correction domain emerges (e.g., frontend components, database migrations):

1. Create the agent file with domain-specific checklists and triage tables
2. Add file routing patterns to the orchestration skill
3. Update sibling deferral tables in existing reviewers
4. Update the agent roster

### When NOT to Split

Don't create a new reviewer unless:
- The domain has **5+ distinct check types** that require specialized knowledge
- Mistakes in this domain are **frequent enough** to justify the agent's context cost
- The domain's checks are **different enough** from existing reviewers to avoid overlap

A reviewer with only 2-3 checks should be merged into the closest existing reviewer.

## Common Mistakes

### Over-Posting

Posting 20+ comments on a PR overwhelms the author. Cap at 8-10 findings per reviewer. Prioritize blocking issues over suggestions.

### Duplicate Findings

When multiple reviewers examine overlapping files (e.g., a Terraform file with secrets), they may flag the same issue. The orchestration layer should deduplicate by file path + line range before presenting.

### Stale Checklists

Review checklists become outdated as the codebase evolves. Include a review date in each reviewer's system prompt and update quarterly.

### Missing Sibling Awareness

Each reviewer should know what the other reviewers check, so it can defer rather than produce shallow findings outside its domain:

```markdown
## Sibling Reviewers

| Finding Type | Defer To |
|-------------|----------|
| Secret path naming issues | secrets-config-reviewer |
| Agent frontmatter validation | agent-config-reviewer |
| Shell script issues in hooks | devops-reviewer |
```
