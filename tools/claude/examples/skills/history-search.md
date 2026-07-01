---
name: history-search
description: Search prior Claude Code conversations across your projects by date window and regex. Use when the user references "what we discussed earlier today" or "in last session about X". Usage - /history-search <pattern> [days=7]
user-invocable: true
allowed-tools: Bash(jq *), Bash(rtk proxy jq *), Bash(grep *), Bash(date *), Bash(wc *)
argument-hint: "<pattern> [days=7]"
---

# history-search

Search `~/.claude/history.jsonl` (user-prompt index) and project-scoped session transcripts under `~/.claude/projects/*/` for prior conversation context.

## Why this exists

The user frequently references prior conversation context across sessions ("we discussed this earlier today", "in last session"). Local memory and `MEMORY.md` don't carry full conversation detail. This skill is the canonical lookup so you stop guessing what was said before.

## Data model

- `~/.claude/history.jsonl` — one line per user prompt across ALL projects. Fields: `display` (prompt text), `timestamp` (Unix ms), `project` (encoded path), `sessionId`. Compact, fast to grep.
- `~/.claude/projects/<encoded-path>/<session-uuid>.jsonl` — full session transcripts including tool calls. Slow to scan; only open after pinpointing a session via the index.

The encoded path mirrors the on-disk clone path with slashes replaced by dashes (e.g. `-Users-<user>-<workspace>-<repo>`).

## Steps

### 1. Parse arguments

Expected: `<pattern> [days=7]`.

- `<pattern>` is a regex (extended), case-insensitive.
- `[days]` defaults to 7. Cap at 90.

If `<pattern>` is missing, ask the user. Don't guess.

### 2. Compute time window

```bash
SINCE_MS=$(( $(date +%s) * 1000 - DAYS * 86400 * 1000 ))
```

### 3. Filter the prompt index

```bash
jq -c --argjson since "$SINCE_MS" --arg pattern "$PATTERN" '
  select(.timestamp >= $since)
  | select(.display | test($pattern; "i"))
  | {ts: (.timestamp / 1000 | strftime("%Y-%m-%d %H:%M")), project, sessionId, display}
' ~/.claude/history.jsonl
```

Use `rtk proxy jq ...` if the output drives a decision — RTK filtering has silently truncated jq output in the past.

### 4. Report — three tiers depending on hit count

- **0 hits:** report verbatim "no match for `<pattern>` in last `<N>` days." Suggest widening the window.
- **1-5 hits:** quote each (ts + project + first 200 chars of `display`). Offer to open a specific session transcript.
- **6+ hits:** group by project + day, return counts. Quote only the first hit per group; ask which group to drill into.

### 5. Drill-down (only on user request)

```bash
SESSION_FILE=~/.claude/projects/<encoded-path>/<session-uuid>.jsonl
jq -c 'select(.type == "user" or .type == "assistant") | {type, ts: .timestamp, text: (.message.content[0].text // .message.content // "")[0:300]}' "$SESSION_FILE"
```

Quote relevant exchanges verbatim. Don't paraphrase.

## Counter-indications

- Do not use to mine for behavior patterns / corrections — that's a separate history-mining tool (different aggregation, different output).
- Do not enumerate full session transcripts in a single response — paginate or summarize, the transcripts are 10K+ lines each.
- Do not pull `display` text from unrelated projects unless the user explicitly asked — privacy boundary.
- Do not use as substitute for `Read`-ing the current file. History tells you what was said, not what the code is right now.
