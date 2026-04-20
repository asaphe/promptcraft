---
name: scan-history
description: Mine conversation history for patterns, repeated corrections, and candidate learnings. Supports date filtering and category scoping. Usage - /scan-history [--since YYYY-MM-DD] [--category terraform|k8s|cicd|secrets|deploy]
user-invocable: true
allowed-tools: Bash(cat *), Bash(jq *), Bash(ls *), Bash(find *), Bash(sort *), Bash(head *), Bash(tail *), Bash(grep *), Read, Grep, Glob, AskUserQuestion
argument-hint: "[--since YYYY-MM-DD] [--category category]"
---

# Scan History

Mine conversation history on demand to discover patterns, repeated corrections, and candidate learnings.

## Steps

### 1. Parse arguments

From `$ARGUMENTS`, extract:

- `--since YYYY-MM-DD` — Only scan sessions after this date (default: 30 days ago)
- `--category` — Filter by domain: `terraform`, `k8s`, `cicd`, `secrets`, `deploy`, `all` (default: `all`)

### 2. Discover sessions

Find conversation history from the Claude projects index:

```bash
# Find project index files
ls ~/.claude/projects/ 2>/dev/null

# Find session files for this project
find ~/.claude/projects/ -name "*.jsonl" -newer {since_date_file} 2>/dev/null | head -50
```

Also check the global history:

```bash
ls -la ~/.claude/history.jsonl 2>/dev/null
```

### 3. Validate and scan sessions

Before parsing, validate the JSONL format by reading the first line of each file:

```bash
head -1 {session_file} | jq -e 'has("type")' > /dev/null 2>&1
```

If validation fails (exit code non-zero), warn the user: "Session file {path} has unexpected format — skipping." and continue to the next file. Do not attempt to parse files that fail validation.

For each valid session file, extract key signals:

```bash
# Count messages and tool calls
jq -r 'select(.type == "assistant") | .message.content[]? | select(.type == "tool_use") | .name' {session_file} | sort | uniq -c | sort -rn
```

**Category detection keywords:**

| Category | Keywords |
|----------|----------|
| terraform | `terraform`, `tfplan`, `workspace`, `module`, `backend`, `state`, `hcl` |
| k8s | `kubectl`, `pod`, `deployment`, `ingress`, `helm`, `karpenter`, `namespace` |
| cicd | `workflow`, `action`, `github`, `dispatch`, `pipeline`, `container`, `ecr` |
| secrets | `secret`, `externalsecret`, `aws-sm`, `tenant-secrets`, `TENANT_SECRETS_JSON` |
| deploy | `deploy`, `rollout`, `release`, `image_tag`, `helm upgrade` |

### 4. Identify patterns

Look for these signals across sessions:

- **Repeated corrections** — User says "no", "wrong", "not that", "I said", "stop" followed by a correction
- **Recurring topics** — Same module/service/workflow appearing in 3+ sessions
- **Long sessions** — Sessions with 50+ tool calls (potential complexity/confusion)
- **Error recovery** — Sequences where a tool call fails and is retried with different parameters

### 5. Extract candidate learnings

For each pattern found, format as:

```text
CANDIDATE LEARNING #N
  Category:    {terraform|k8s|cicd|secrets|deploy}
  Pattern:     {what was observed}
  Frequency:   {how many times across how many sessions}
  Evidence:    {specific session references}
  Proposed:    LEARNING: [{category}] {description} / CONTEXT: {what happened} / SCOPE: project
```

### 6. Present findings summary

```text
History Scan Results
═══════════════════

Scanned: {N} sessions from {date_range}
Categories: {breakdown by category}

Top Patterns:
  1. [{category}] {pattern} — {N} occurrences across {M} sessions
  2. [{category}] {pattern} — {N} occurrences across {M} sessions
  ...

Candidate Learnings: {count}
```

### 7. Interactive approval

Present each candidate learning one at a time. For each, ask the user:

1. **Approve** — Classify and save (see step 8)
2. **Edit** — Let the user modify the wording, then save
3. **Reject** — Skip this candidate

### 8. Save approved learnings

Classify each approved learning using the full five-tier system from `CLAUDE.md` Learning Classification:

| Classification | Target | Shared? |
|---------------|--------|---------|
| **Team-wide** (any developer in this repo) | `.claude/rules/{subdirectory}/{rule}.md` | Yes (git) |
| **Agent-specific** (one agent's domain) | `.claude/agents/{agent}.md` | Yes (git) |
| **Personal global** (user workflow preference) | `~/.claude/CLAUDE.md` | No |
| **Personal project** (user preference, this project only) | `CLAUDE.local.md` or auto memory | No |
| **Temporary/experimental** | `~/.claude/projects/<project>/memory/` | No |

Use the `learning-classifier` agent when classification is ambiguous.

Format team-wide and agent-specific rules as: `- **Rule title** — What to do and why.` No dates, confirmation counts, or metadata — just actionable rules.

## Safety

- Read-only on history files — never modifies conversation history
- Only writes to `.claude/rules/` or `.claude/agents/` after explicit user approval per entry
- Handles missing/corrupt session files gracefully (skip and note)
- Respects `--since` filter to avoid scanning unnecessarily large history
