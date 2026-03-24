# Operational Rules Guide

How to design, capture, and maintain `.claude/rules/` — auto-loaded operational rules born from real incidents.

## What Operational Rules Are

Operational rules are hard-won lessons from real sessions — corrections, near-misses, and patterns that should be followed automatically in every conversation. They live in `.claude/rules/*.md` and are **auto-loaded into every conversation's context**, unlike on-demand docs that must be explicitly read.

Each rule is a single bullet:

```markdown
- **Rule title** — What to do and why.
```

Rules are imperative and actionable. They don't explain background — they state the behavior.

## Rules vs Docs vs Specs

| Type | Location | Loading | Purpose |
| ---- | -------- | ------- | ------- |
| **Rules** | `.claude/rules/*.md` | Auto-loaded (always in context) | Behavioral guardrails, safety patterns, mandatory protocols |
| **Docs** | `.claude/docs/*.md` | On-demand (read when needed) | Reference material, architecture details, build commands |
| **Specs** | `.claude/specs/*.md` | On-demand (read when needed) | RFC-style standards, CI/CD protocols, naming conventions |

**The key distinction:** Rules are cheap (one bullet each, always loaded) and prevent mistakes. Docs are expensive (detailed reference, loaded on demand) and provide knowledge. Don't put reference material in rules — it wastes context tokens on every conversation.

## Rule Format

Every rule follows this structure:

```markdown
- **Short imperative title** — Detailed explanation of what to do, why, and what happens if you don't. Include specific commands or patterns when applicable.
```

**Good examples:**

```markdown
- **Always resolve the running image tag before apply** — Modules default `image_tag` to `main` via `coalesce(var.image_tag, "main")`. Before any manual apply: (1) check the running image, (2) pass it explicitly. Never rely on the module default.

- **Read before editing — no parallel edits without reads** — Never issue an Edit call for a file not read in the current turn. When editing multiple files, read them all first, then edit. After context continuations, re-read before editing.

- **Failing CI checks are never dismissible as pre-existing** — A failing check on the main branch blocks everyone and must be fully investigated regardless of which commit introduced it. Never write off a check failure as "not caused by our changes."
```

**Bad examples:**

```markdown
- Be careful with Terraform.  (too vague — what specifically?)
- **Important** — Remember to check things before deploying. (no actionable behavior)
- **Terraform apply safety** — When running terraform apply, you should make sure to check the plan output first and verify that the changes look correct. Also remember to check the workspace and make sure you're in the right one. Additionally... (too long — should be split into separate rules)
```

## Rules Capture Protocol

Rules emerge from real sessions. The capture lifecycle:

### 1. Recognize

Something goes wrong (or almost goes wrong) during a session:

- A command targeted the wrong environment
- A file was edited without being read first
- An assumption turned out to be incorrect
- A diagnostic was dismissed as "not our problem" and later caused issues

### 2. Propose

Format the lesson as a candidate rule:

```text
CANDIDATE RULE:
  Title: Re-verify state after context continuation
  Body: After any context continuation or session handoff, re-read actual files for current git branch, workspace, image tag, and target workflow. Never rely solely on continuation summaries for operational values.
  Category: operational-safety
```

### 3. Classify

Determine where the rule belongs:

| Scope | Destination |
| ----- | ----------- |
| Applies to one specific agent's domain | Add to that agent's definition (`.claude/agents/<agent>.md`) |
| Applies to all agents / general behavior | Add to `.claude/rules/<category>.md` |
| Applies only to one project | Project `.claude/CLAUDE.md` |
| Applies across all projects | Personal `~/.claude/CLAUDE.md` |

### 4. Format

Write as a single bullet following the standard format. Strip session-specific details — the rule should be general enough to apply next time.

### 5. Commit

Include rule additions in the current PR alongside the code changes that prompted them. Rules are code — they deserve review.

## Rule Categories

Organize rules by domain into separate files:

| File | Content |
| ---- | ------- |
| `operational-safety.md` | Session management, edit discipline, failure analysis, destructive operations |
| `terraform-apply.md` | Plan/apply safety, workspace management, state operations |
| `deployment.md` | Deployment-specific patterns, environment configuration, cross-env risks |
| `ci-runners.md` | CI/CD runner configuration, lint tool quirks, check investigation |
| `pr-review.md` | Review routing, finding verification, posting protocol |

You don't need all of these from day one. Start with `operational-safety.md` and add categories as patterns emerge.

## Rule Authoring Principles

**Lead with positive guidance** — "Always verify the workspace before apply" is followed more reliably than "Never apply to the wrong workspace." Positive framing tells the agent what to do; negative framing only tells it what to avoid, leaving the correct behavior ambiguous. Reserve NEVER/DON'T for genuinely dangerous operations (state mutations, force-push, production deploys) where the emphasis is warranted.

**Capture the principle, not just the incident** — A rule prompted by a specific mistake should prevent the entire class of mistake, not just the exact scenario. Ask: "Would this rule also prevent the next variant of this problem?" If it only catches the exact case encountered, extract the general principle. Example: "Don't consolidate config-X without diffing" → "Diff all environment variants before consolidating shared config."

**Instruction weight: WHAT + WHEN** — Every rule title should answer two questions: what to do, and when to do it. "Re-verify state after context continuation" is better than "Verify state" because it specifies the trigger condition. Without the WHEN, the agent either applies the rule everywhere (wasteful) or nowhere (useless).

**Keep rule files focused** — Each file should contain 3-8 rules maximum. If a file grows beyond 8, split by subdomain. Total auto-loaded rules across all files should stay under 150-200 (the instruction budget ceiling). Count with: `grep -c '^\- \*\*' .claude/rules/**/*.md`.

## Rule Deprecation and Auditing

Rules accumulate but rarely get pruned. Stale rules waste context tokens and can conflict with newer guidance.

**Quarterly audit protocol:**

1. **Count total rules**: `grep -c '^\- \*\*' .claude/rules/**/*.md` — if above 150, prune is overdue
2. **Check last modification**: `git log --format='%ai' -1 .claude/rules/<file>` — files unchanged for 6+ months are candidates
3. **Search session history**: For each candidate rule, search recent sessions for the rule title. If never triggered, consider retiring
4. **Check for contradictions**: Rules added during different incidents may conflict — read all rules in the same domain together
5. **Verify altitude**: Re-read each rule and ask "Is this still the right level of specificity?" Rules written during an incident are often too narrow

**Retirement options:**

- **Move to `.claude/docs/`** — Becomes an on-demand reference instead of always-loaded. Good for rules that are valid but rare.
- **Merge into a parent rule** — When multiple narrow rules share a principle, consolidate into one that captures the class.
- **Delete entirely** — When the underlying system has changed and the rule no longer applies.

## Context Budget Management

Rules are always-loaded — every bullet consumes context tokens on every conversation. The instruction budget is ~150-200 rules (Claude Code's system prompt uses ~50, leaving ~100-150 for your config). Exceeding this degrades instruction-following quality.

### Measure Your Budget

```bash
# Count always-loaded rule bullets
grep -c '^- \*\*' .claude/rules/**/*.md | awk -F: '{sum+=$2} END{print "Total:", sum}'

# Estimate token cost
cat .claude/CLAUDE.md .claude/rules/**/*.md | wc -c | awk '{printf "~%d tokens\n", $1/4}'
```

### Reduce With paths: Frontmatter

Rules scoped with `paths:` frontmatter only load when working in matching directories:

```markdown
---
paths:
  - "devops/terraform/**"
---
# Terraform Apply Safety

- **Always resolve the running image tag** — ...
```

This rule loads when editing Terraform files but not when working on Python or TypeScript. Without frontmatter, it loads in every conversation regardless of context.

**Impact:** A project with 150 devops rules and 70 general rules (220 total) can drop to ~80 always-loaded by scoping all domain-specific rules. Terraform rules load only for Terraform work, CI rules only for workflow files, etc.

### Move Context-Specific Rules to On-Demand Docs

Some rules are only relevant during specific activities (PR review, doc writing, investigation). Move these from `.claude/rules/` (always-loaded) to `.claude/docs/` (on-demand) and add load pointers:

1. **In CLAUDE.md** — Add an on-demand reference:
   ```markdown
   - **Reviewing a PR?** Read `.claude/docs/pr-workflow.md`
   ```

2. **In skills** — Add a read instruction at the top of the skill:
   ```markdown
   Before starting, read `.claude/docs/pr-workflow.md` for behavioral rules.
   ```

This way the content loads only when the skill is invoked or the user navigates to a relevant task — not on every conversation start.

### Budget Allocation Guidelines

| Category | Target | Notes |
|----------|--------|-------|
| Always-loaded general rules | 30-50 | Safety, editing discipline, git workflow |
| Domain-specific (with paths:) | 80-120 | Only load when working in their domain |
| On-demand docs | Unlimited | Loaded by skills and CLAUDE.md pointers |
| CLAUDE.md | 30-40 | Project overview, agent roster, standards |

## Anti-Patterns

### Rules that are too vague

```markdown
- **Be careful** — Make sure to check things before doing operations.
```

This tells the agent nothing actionable. What things? Which operations? What does "check" mean?

### Rules that are too long

If a rule exceeds 3-4 lines, it's probably a doc, not a rule. Split it into multiple rules or move the reference material to `.claude/docs/`.

### Rules that duplicate docs

```markdown
- **Module structure** — The terraform modules are organized as: 01-network, 02-ecr, 03-eks...
```

This is reference material, not a behavioral rule. Put it in a doc and reference it.

### Rules without a trigger condition

```markdown
- **Use the correct workspace** — Always make sure you're in the right Terraform workspace.
```

When does this apply? A better version:

```markdown
- **Workspaces — always list before creating** — Run `terraform workspace list` before any workspace operation. Never create a workspace without presenting the proposed name and getting approval.
```

## Session Mining

Periodically review past sessions for patterns that haven't been captured as rules:

1. **Identify repeated corrections** — When the user said "no", "wrong", "stop", "not that" and provided a correction
2. **Find recurring tool call failures** — Same command failing across multiple sessions (indicates a missing safety check)
3. **Spot long recovery sequences** — Sessions with 50+ tool calls on a single issue (indicates missing triage knowledge)
4. **Track recurring topics** — The same module, service, or workflow appearing in 3+ sessions

For each pattern found, run through the capture protocol above.

## CLAUDE.md Integration

Reference the rules system in your project's `.claude/CLAUDE.md`:

```markdown
## Operational Rules (`.claude/rules/`)

Auto-loaded rules from past operational experience live in `.claude/rules/`. These are always in context.

When you encounter a correction, failure, or unexpected behavior during a session, proactively propose capturing it as a rule. Classify: agent-specific -> agent definition, team-wide -> `.claude/rules/`. Format each rule as a single bullet: `- **Rule title** — What to do and why.`
```

This tells the AI to actively participate in rule capture — it should propose new rules when it observes patterns.
