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
