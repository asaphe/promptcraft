# Automated Learning System Guide

How to build a self-improving Claude Code setup that captures operational knowledge from mistakes, classifies learnings by scope, and surfaces them across sessions using hooks.

## The Problem

Claude Code's learning capture relies on agents noticing corrections during a session. This is reactive — if the agent misses a correction or the session ends before a rule is proposed, the learning is lost. There's also no structured way to distinguish between learnings that should be shared with the team vs those that are personal preferences.

## Architecture

The learning system has three layers:

```
                  +---------------------------------+
                  |  Layer 1: Automated Hooks        |
                  |  (SessionEnd, SessionStart,      |
                  |   PreCompact)                    |
                  +----------------+-----------------+
                                   | writes/reads
                  +----------------v-----------------+
                  |  Layer 2: Staging File            |
                  |  pending-learnings.md             |
                  |  (in auto-memory dir)             |
                  +----------------+-----------------+
                                   | reviewed by
                  +----------------v-----------------+
                  |  Layer 3: Classification          |
                  |  learning-classifier agent        |
                  |  -> .claude/rules/ (team)         |
                  |  -> .claude/agents/ (agent)       |
                  |  -> auto memory (personal)        |
                  +---------------------------------+
```

### Layer 1: Automated Hooks

Three hooks capture learning signals without manual intervention:

| Hook | Event | Async? | Purpose |
| ---- | ----- | ------ | ------- |
| `session-end-learnings.sh` | `SessionEnd` | Yes | Scans transcript for corrections and retry patterns |
| `session-start-learnings.sh` | `SessionStart` | No (5s timeout) | Checks for pending learnings; nudges about auto memory |
| `precompact-preserve.sh` | `PreCompact` (auto only) | Yes | Preserves correction context before compaction loses it |

**Why these specific events:**

- `SessionEnd` is the right time to scan — the session is over, async execution has zero UX impact.
- `SessionStart` is the right time to surface — the agent has full context to evaluate candidates.
- `PreCompact` catches corrections in long sessions that might compact before ending.
- `Stop` (fires every turn) was considered and rejected — a prompt-type Stop hook adds latency to every interaction. A command-type Stop hook is fast but fires too frequently for transcript scanning.

### Layer 2: Staging File

Candidates are written to `~/.claude/projects/<project>/memory/pending-learnings.md` — the user's auto-memory directory. This is per-user, per-project, and persists across sessions.

Each candidate includes:

```markdown
## Session <id> (<timestamp>)

- **Working directory:** /path/to/repo
- **Tool calls:** 47
- **Corrections detected:** 3
- **Retry patterns:** 1

### Correction signals

\`\`\`
no, wrong workspace — use staging not prod
I said use the discovery key, not the team name
\`\`\`
```

### Layer 3: Classification

When the next session starts and pending learnings exist, the agent reviews them. For ambiguous cases, the `learning-classifier` agent determines the target:

| Signal | Classification | Target |
| ------ | ------------- | ------ |
| Applies to any developer in the repo | **Team-wide** | `.claude/rules/{subdirectory}/{rule}.md` |
| Specific to one agent's domain | **Agent-specific** | `.claude/agents/{agent}.md` |
| User workflow preference | **Personal global** | `~/.claude/CLAUDE.md` |
| User preference for this project | **Personal project** | `CLAUDE.local.md` or auto memory |
| Temporary / unverified | **Memory only** | `~/.claude/projects/<project>/memory/` |

## Implementation

### Hook Scripts

All hooks receive JSON on stdin with `transcript_path`, `session_id`, `cwd`, and event-specific fields. Stdin is small hook metadata JSON (not the full transcript) — safe to buffer with `INPUT=$(cat)`. The scripts derive the memory directory from `transcript_path` — the auto-memory directory is always a sibling `memory/` folder under the same project path.

#### session-end-learnings.sh

Scans the transcript JSONL for:

1. **User corrections** — Messages containing "no", "wrong", "not that", "I said", "actually,", etc.
2. **Retry patterns** — Same tool called consecutively (indicates a failed attempt + retry)
3. **Long sessions** — 50+ tool calls (may indicate complexity or confusion)

Only writes if 2+ signals detected or session had 50+ tool calls. This threshold prevents noise from normal "no, cancel that" interactions.

```bash
# Signal detection (simplified)
CORRECTIONS=$(jq -r '
  select(.type == "user") | .message.content // [] |
  if type == "array" then .[] else . end |
  if type == "object" then .text // empty else . end
' "$TRANSCRIPT_PATH" 2>/dev/null | \
  grep -iE '(^no[,. !]|wrong|not that|I said)' | \
  head -10 || true)

RETRIES=$(jq -r '
  select(.type == "assistant") | .message.content // [] | .[] |
  select(.type == "tool_use") | .name
' "$TRANSCRIPT_PATH" 2>/dev/null | \
  uniq -d | head -5 || true)

TOOL_COUNT=$(jq -r '
  select(.type == "assistant") | .message.content // [] | .[] |
  select(.type == "tool_use") | .name
' "$TRANSCRIPT_PATH" 2>/dev/null | wc -l | tr -d ' ' || true)
TOOL_COUNT=${TOOL_COUNT:-0}
```

**Pipefail safety:** Every `jq` pipeline must end with `|| true`. Under `set -eo pipefail`, if `jq` encounters malformed JSON (truncated transcript, partial write), it exits non-zero and `pipefail` propagates that through the pipe, silently aborting the script. The `CORRECTIONS` pipeline also uses `grep` which returns exit code 1 on no-match — same risk.

#### session-start-learnings.sh

Outputs text to stdout (SessionStart stdout is injected into Claude's context):

- If `pending-learnings.md` exists and has content, tells Claude to review candidates
- If `MEMORY.md` is empty, nudges about auto memory usage

The nudge is lightweight — it only fires if the memory file doesn't exist or is empty.

#### precompact-preserve.sh

Scans the **last 200 lines** of the transcript (not the whole file — compaction means the file is large). Writes any corrections found to the same `pending-learnings.md` staging file.

### Hook Registration

Register in `.claude/settings.json` (shared with team via git):

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/session-start-learnings.sh",
            "timeout": 5
          }
        ]
      }
    ],
    "SessionEnd": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/session-end-learnings.sh",
            "async": true,
            "timeout": 30
          }
        ]
      }
    ],
    "PreCompact": [
      {
        "matcher": "auto",
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/precompact-preserve.sh",
            "async": true,
            "timeout": 15
          }
        ]
      }
    ]
  }
}
```

Key design choices:

- `SessionStart` is **synchronous** — its stdout becomes Claude's context, so it must complete first. The 5s timeout keeps it fast.
- `SessionEnd` and `PreCompact` are **async** — they run in the background with no UX impact.
- `PreCompact` uses `matcher: "auto"` — only fires on automatic compaction, not manual `/compact`.

### Learning Classifier Agent

A lightweight agent (Haiku model, 10 max turns) that:

1. Reads the proposed learning
2. Checks agent definitions to see if it maps to one agent's domain
3. Checks existing rules for duplicates
4. Returns classification with reasoning

```yaml
---
name: learning-classifier
description: Classifies proposed learnings as team-wide, agent-specific, or personal.
tools: Read, Glob, Grep
model: haiku
maxTurns: 10
---
```

Using Haiku keeps it fast and cheap. The agent only needs to read a few files and make a classification decision.

### Review Agents

The project has three review agents that produce read-only PR findings:

| Agent | Scope |
| ----- | ----- |
| **devops-reviewer** | Terraform, GitHub Actions, Dockerfiles, shell scripts (including hook scripts), Helm charts |
| **secrets-config-reviewer** | Secret tfvars, helm template secret refs, ExternalSecret configs, naming convention |
| **agent-config-reviewer** | `.claude/` agent definitions, skills, commands, CLAUDE.md, hooks, plugin validation |

The `secrets-config-reviewer` validates the highest-frequency correction domain — secrets and MT configuration. It checks secret path naming convention, tier classification, TSJ mechanism selection per app, `USE_SECRET_SERVICE` consistency, `mt_secret_template_mode` correctness, token syntax (`.tfvars` uses `<TOKEN>`, `.yaml.tftpl` uses `${variable}`), and cross-environment template consistency.

The `agent-config-reviewer` includes hook and plugin validation: verifying that referenced script paths exist, are executable, have valid timeout/async/matcher fields, and that plugin script copies are byte-identical to their source-of-truth counterparts (or symlinked).

The `devops-reviewer` includes hook-script-specific checks: `jq` filters matching transcript JSONL format, `grep` patterns using `|| true` for pipefail safety, and output written to appropriate directories.

### CLAUDE.md Integration

Add a Learning System section to your project CLAUDE.md:

```markdown
## Learning System

The learning system captures operational knowledge from mistakes, corrections,
and recurring patterns. It has three layers: automated hooks that detect signals,
a classification system that routes learnings to the right location, and a manual
`/scan-history` skill for deeper analysis.

### Learning Classification

| Signal | Classification | Target |
|--------|---------------|--------|
| Applies to any developer in this repo | Team-wide | `.claude/rules/{subdirectory}/{rule}.md` |
| Specific to one agent's domain | Agent-specific | `.claude/agents/{agent}.md` |
| User workflow preference | Personal global | `~/.claude/CLAUDE.md` |
| User preference for this project only | Personal project | `CLAUDE.local.md` or auto memory |
| Temporary or experimental insight | Memory only | `~/.claude/projects/<project>/memory/` |
```

## Rule Retirement

Rules accumulate over time. Without maintenance, they bloat the context window and may become outdated.

### Review Date Headers

Add a review date comment to each rules file:

```markdown
<!-- Last reviewed: 2026-02-27 -->
# Terraform Apply Safety Rules

- **Rule one** — ...
```

### Periodic Review

When running `/scan-history`, cross-reference existing rules against recent sessions:

- Rules that were **never triggered** in the last 30 days may be candidates for retirement
- Rules that were **violated frequently** may need strengthening or better placement
- Rules that reference **deprecated tools or patterns** should be updated or removed

## Rules Organization

As rules accumulate, a flat `.claude/rules/` directory creates token pressure — every rule loads into every session regardless of relevance. Organize rules into subdirectories with conditional loading using the `paths:` frontmatter feature.

### Directory Structure

```
.claude/rules/
+-- general/              # Always loaded (no paths: filter)
|   +-- operational-safety.md
|   +-- pr-review.md
+-- devops/               # Loaded only when working on devops/ or .github/ files
|   +-- ci-runners.md
|   +-- clickhouse-backup.md
|   +-- mt-deployment.md
|   +-- terraform-apply.md
```

### `paths:` Frontmatter

Add a YAML frontmatter block to conditionally load a rule:

```markdown
---
paths: ["devops/terraform/**", "devops/helm-reusable-chart/**"]
---
# Terraform Apply Safety Rules
- **Rule** -- Description.
```

Claude Code only loads this rule when the session involves files matching those glob patterns. Without `paths:`, the rule loads unconditionally.

### Design Principles

- **`general/`** is for cross-cutting rules (safety, review standards) — no `paths:` filter, always loaded
- **Domain subdirectories** (e.g., `devops/`, `backend/`, `frontend/`) use `paths:` to scope loading
- **Agents are not affected** — agents reference rules explicitly via their Key References section (Read tool), bypassing the auto-loading mechanism entirely
- **New teams** add their own subdirectory with appropriately scoped `paths:` patterns

This keeps token usage proportional to task relevance — a TypeScript session doesn't load Terraform rules, and vice versa.

## Plugin Distribution

For teams with multiple repositories, package the learning system as a Claude Code plugin:

```
surfai-learning/
+-- .claude-plugin/
|   +-- plugin.json
+-- skills/
|   +-- scan-history/
|       +-- SKILL.md
+-- agents/
|   +-- learning-classifier.md
+-- hooks/
|   +-- hooks.json
+-- scripts/
    +-- session-end-learnings.sh -> ../../../hooks/session-end-learnings.sh
    +-- session-start-learnings.sh -> ../../../hooks/session-start-learnings.sh
    +-- precompact-preserve.sh -> ../../../hooks/precompact-preserve.sh
```

**Script symlinks:** Plugin scripts in `scripts/` are symlinks to the canonical `hooks/*.sh` files. This eliminates the duplicate-maintenance burden — edits to the repo-level hooks are automatically reflected in the plugin. Agent and skill files are still copies (symlinks don't work for those in the plugin loader).

Install for the team:

```bash
claude plugin install surfai-learning --scope project
```

This writes to `.claude/settings.json`, which is committed to git so every team member gets it on clone.

**Important:** If hooks are already configured in the project's `settings.json`, don't also install the plugin in the same project — the hooks would fire twice. The plugin is for **other repos** that want the same learning system.

## Evolution History

This system evolved through three stages:

1. **Flat learnings file** — Dated entries with confirmation counts and session references. Too much metadata, not actionable enough.
2. **Domain-split learnings** — Split by category, promoted confirmed learnings to docs. Better organization, but still too verbose.
3. **Pure rules + automated hooks** — Stateless actionable bullets in `.claude/rules/`, automated capture via hooks. Current state.

The key insight: **rules should carry zero provenance**. Dates, confirmation counts, and session references are noise that wastes context tokens. The rule either stands on its own as useful guidance or it doesn't.

## Complementary Tools

| Tool | Purpose | Relationship to Learning System |
| ---- | ------- | ------------------------------- |
| **Auto memory** | Per-user persistent notes | Stores personal learnings and pending candidates |
| **`/scan-history` skill** | On-demand history mining | Deeper analysis than automated hooks can provide |
| **`learning-classifier` agent** | Classification assistant | Resolves ambiguous personal vs team classification |
| **`.claude/rules/`** | Team-shared operational rules | Final destination for team-wide learnings |

## Key Principles

1. **Automate detection, not classification** — Hooks detect signals; humans approve and classify. Fully automated rule creation would introduce noise.
2. **Zero UX impact** — SessionEnd and PreCompact hooks are async. SessionStart is sync but fast (file existence check).
3. **Personal vs shared is a spectrum** — Use the classification table, but when in doubt, start in auto memory and promote to rules after confirming the pattern recurs.
4. **Rules carry no metadata** — No dates, counts, or session references. Pure actionable bullets.
5. **Review date headers are for humans** — The `<!-- Last reviewed -->` comment helps humans track staleness; Claude ignores HTML comments in context.
6. **Pipefail safety is non-negotiable** — Every `jq` and `grep` pipeline in hook scripts must end with `|| true`. A silent hook abort means lost learnings with no visible error.
7. **Symlink plugin scripts to the canonical hooks** — Eliminates the duplicate-maintenance burden that caused bug propagation (e.g., missing `|| true` fixes needing to be applied in two places).
8. **Organize rules into scoped subdirectories** — Use `paths:` frontmatter to conditionally load domain-specific rules. General rules (no `paths:`) always load; domain rules only load when relevant files are in scope. This keeps token usage proportional to task relevance as the rule set grows.
