# Session Analytics Guide

How to mine Claude Code session history to find tool call waste patterns and optimization opportunities.

## Why Analyze Sessions

Rules and hooks are reactive — you add them after a mistake. Session analytics is proactive: mine your data to find systemic waste patterns before they become habits. A single analysis can reveal thousands of redundant tool calls across hundreds of sessions.

## Data Sources

| Source | Location | Contains |
|--------|----------|----------|
| Session JSONL | `~/.claude/projects/*/*.jsonl` | Full conversation: tool calls, results, user messages |
| Subagent sessions | `~/.claude/projects/*/subagents/*.jsonl` | Subagent conversations (exclude from main analysis) |
| History | `~/.claude/history.jsonl` | User messages only (lightweight, cross-project) |
| Quality metrics | `~/.claude/metrics/session-quality.jsonl` | Per-session metrics (if using [session-quality-capture](../examples/hooks/session-quality-capture/) hook) |

## Useful Queries

### Tool Call Frequency

```bash
# Top tool names across all sessions
find ~/.claude/projects -name "*.jsonl" -not -path "*/subagents/*" \
  | xargs jq -r 'select(.type == "assistant") | .message.content[]? | select(.type == "tool_use") | .name' 2>/dev/null \
  | sort | uniq -c | sort -rn | head -20
```

### Command Patterns (Bash)

```bash
# Most common CLI commands
find ~/.claude/projects -name "*.jsonl" -not -path "*/subagents/*" \
  | xargs grep -oh '"command":"[^"]*"' 2>/dev/null \
  | sed 's/"command":"//;s/"//' \
  | awk '{print $1, $2}' | sort | uniq -c | sort -rn | head -30
```

### AWS Service Usage

```bash
# Which AWS services are called most
find ~/.claude/projects -name "*.jsonl" -not -path "*/subagents/*" \
  | xargs grep -oh 'aws [a-z-]*' 2>/dev/null \
  | sort | uniq -c | sort -rn | head -20
```

### Failure Rate

```bash
# Sessions with highest bash failure rates
find ~/.claude/projects -name "*.jsonl" -not -path "*/subagents/*" \
  | xargs grep -c '"exit_code":[1-9]' 2>/dev/null \
  | grep -v ':0$' | sort -t: -k2 -rn | head -20
```

### Most-Read Files

```bash
# Which files are read most across all sessions
find ~/.claude/projects -name "*.jsonl" -not -path "*/subagents/*" \
  | xargs grep -oh '"file_path":"[^"]*"' 2>/dev/null \
  | sort | uniq -c | sort -rn | head -30
```

### Session Size Distribution

```bash
# Largest sessions by line count
find ~/.claude/projects -name "*.jsonl" -not -path "*/subagents/*" \
  | xargs wc -l 2>/dev/null | sort -rn | head -20
```

## The Data-Driven Optimization Loop

1. **Mine** — Run the queries above to get a baseline
2. **Categorize** — Group waste by type (polling, boilerplate, redundant reads, etc.)
3. **Prioritize** — Rank by estimated call count, then build hooks for the top 3-5
4. **Measure** — Re-run the same queries after a month to verify reduction
5. **Repeat** — Quarterly cadence is sufficient; patterns change slowly

## Behavioral Analysis: Multi-Agent Pattern

Tool-call waste analysis (above) is the easy half: it surfaces *what Claude does too much of*. The harder half is *what Claude gets wrong* — recurring corrections, repeated user asks, review misses. That data is in the same JSONL files but harder to query because it lives in the conversation, not in tool calls.

A repeatable approach is to run four analyses in parallel as background subagents, each with a focused brief:

| Track | What it mines | Output |
|-------|---------------|--------|
| **Frustrations** | User correction patterns (`"no, wrong"`, `"stop"`, `"why did you"`, `"I told you"`) in `history.jsonl`, then session-context lookup for top themes | List of recurring corrections, each cross-referenced against existing `CLAUDE.md` rules |
| **Repeated asks** | Topics queried across multiple distinct sessions in `history.jsonl` (same question 3+ times in 90 days) | Themes signaling missing docs, missing memory, or recurring operational tasks ripe for automation |
| **Review misses** | Patterns like `"you missed"`, `"what about"`, `"did you check"` in transcripts; correlate to what was being reviewed/fixed | Categories of miss (sibling files, list-completeness, post-push verification, etc.) |
| **Self-investigation** | Hook fire counts, session-size outliers, command frequency, failure rates — fills gaps the agent tracks miss | Quantitative baseline + cross-cutting evidence |

Run them as background jobs (each on Sonnet 4.6 is plenty), let them write to separate `/tmp/*-analysis.md` files, then synthesize the four reports into one prioritized findings doc. A single human-driven analysis takes a few hours; this approach gives equivalent depth in ~20 minutes of wall time.

### Recency-Verification Step

Before acting on any finding, re-grep `history.jsonl` with date cutoffs:

```bash
python3 -c "
from datetime import datetime, timezone, timedelta
now = datetime.now(timezone.utc)
for days in [7, 14, 30, 60]:
    print(f'{days}d ago: {int((now - timedelta(days=days)).timestamp() * 1000)}')
"
```

For each finding, count occurrences in the last 14 / 30 / 60 days and tier:

| Tier | Last hit | Last 14d | Action |
|------|----------|----------|--------|
| **Active** | Today / yesterday | ≥1 occurrence | Fix now — the rule isn't sticking |
| **Recent** | < 30 days | 0–4 occurrences | Watch — rule may be working slowly |
| **Cooling** | 30–60 days | 0 occurrences | Skip unless it recurs |
| **Stale** | > 60 days, 0 in last 30 | 0 | Drop or backlog — pattern naturally cooled OR a previous rule already worked |

This step prevents "ghost-fixing" — adding a rule for a pattern that stopped happening months ago because a previous fix already addressed it. Cross-reference with `git log` on the rules file: if a relevant rule was committed *between* the latest occurrence and today, the rule is likely working and the finding is stale.

### What to Expect

Realistic baseline from one analysis (~80 unique sessions over 30 days):

- 100–200 corrections across all sessions (~1.5–2 per session)
- 5–10 distinct recurring themes worth a rule
- 1–2 themes already addressed by a prior rule (the rule is working, drop the finding)
- 3–5 themes need a new rule or a hook
- 1–2 themes need a script or skill (operational repetition, not a knowledge gap)

### Example Baseline

From an analysis of 716 sessions / 86,693 tool calls:

| Waste Category | Calls | % of Total | Fix |
|---------------|-------|-----------|-----|
| CI polling (sleep + status check) | 5,700 | 6.6% | [CI polling guard](../examples/hooks/ci-polling-guard/) |
| AWS auth boilerplate (export + profile) | 6,700 | 7.7% | [AWS auth check](../examples/hooks/aws-auth-check/) |
| Sequential secret reads | 2,800 | 3.2% | Batch script |
| kubectl --context repetition | 1,200 | 1.4% | [kubectl context inject](../examples/hooks/kubectl-context-inject/) |
| 1Password re-reads | 700 | 0.8% | [1Password read guard](../examples/hooks/op-read-guard/) |
| **Total addressable** | **~17,100** | **~20%** | |

## Hook Ordering Matters

When multiple PreToolUse hooks fire on the same command, they run sequentially in registration order. If one hook rewrites the command (via `updatedInput`), the next hook sees the rewritten version. Plan your hook order:

1. **Rewrite hooks** first (RTK rewrite, context inject)
2. **Proxy/bypass hooks** second (secretsmanager proxy — needs to see post-rewrite command)
3. **Guard hooks** last (destructive guard, polling guard — final gate before execution)

## POSIX Compatibility

macOS ships with BSD `grep`, which uses POSIX Extended Regular Expressions (ERE) in `-E` mode. **PCRE shortcuts don't work:**

| PCRE (broken on macOS) | POSIX ERE (works everywhere) |
|------------------------|------------------------------|
| `\s` | `[[:space:]]` or literal space |
| `\d` | `[0-9]` |
| `\b` | Not available (use anchoring or `grep -w`) |
| `\S` | `[^[:space:]]` |

Always test hooks on your actual OS before registering. A regex that works in testing on Linux may silently fail on macOS.

## Related Resources

- [Hooks Guide](hooks-guide.md) — Hook types, registration, and design patterns
- [Session Quality Capture](../examples/hooks/session-quality-capture/) — Automated per-session metrics
- [Best Practices](claude-best-practices.md) — Context budget and optimization principles
