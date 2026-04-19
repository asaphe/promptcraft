# Session Quality Capture

A **Stop** hook that records session-level metrics to a JSONL file when each Claude Code session ends.

## Why

Tracking session quality quantitatively — rather than hoping rules prevent all mistakes — reveals patterns that prose rules miss. Correction counts show which sessions had friction. Tool call counts show session complexity. PR edit counts show drafting discipline.

Over time, the metrics surface trends: Are corrections decreasing as you add rules? Do high-tool-call sessions correlate with more corrections? Which projects generate the most friction?

## Metrics Captured

| Metric | Source | What It Shows |
|--------|--------|---------------|
| `tool_calls` | Session JSONL | Session complexity and length |
| `corrections` | User message patterns | Agent alignment quality |
| `pr_body_edits` | Companion hook temp files | PR drafting discipline |
| `cost_usd` | `session-cost.py` | Actual API spend per session |
| `session_id` | Hook input | Session identification |
| `timestamp` | System clock | When the session ended |
| `cwd` | Hook input | Which project was active |

### Correction Detection

Corrections are detected by pattern-matching user messages for frustration markers:

```text
no.*wrong | stop doing | not that | I said | don't do | shouldn't | why did you
```

This is a heuristic — it catches clear corrections but may miss subtle ones. The goal is trend detection, not perfect accuracy.

## Setup

Register as a Stop hook in `~/.claude/settings.json`:

```json
{
  "hooks": {
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "/path/to/session-quality-capture.sh"
          }
        ]
      }
    ]
  }
}
```

## Cost Tracking

The hook includes `session-cost.py` to calculate actual API cost at session end. It reads token usage directly from the session JSONL (input, cache_creation, cache_read, output) and applies per-model pricing.

Pricing is bundled in `session-cost.py` and reflects published rates. Update it when Anthropic changes pricing.

The script can also be used standalone:

```bash
session-cost               # cost for the current directory's latest session
session-cost /path/to/session.jsonl  # specific file
session-cost --json        # machine-readable output
```

Add a shell function in your `~/.zshrc` or `~/.bashrc`:

```bash
session-cost() {
  python3 ~/.claude/scripts/session-cost.py "${1:-$PWD}"
}
```

## Output

Appends one JSON line per session to `~/.claude/metrics/session-quality.jsonl`:

```json
{"session_id":"abc123","timestamp":"2025-03-31T12:00:00Z","cwd":"/home/user/project","tool_calls":142,"corrections":1,"pr_body_edits":0,"cost_usd":0.1823}
```

## Companion Hooks

Works with [pr-edit-counter](../pr-edit-counter/) — reads and cleans up its temp files (`/tmp/claude-pr-edit-count-*`) at session end.

## Analyzing Metrics

```bash
# Average tool calls per session
jq -s '[.[].tool_calls] | add / length' ~/.claude/metrics/session-quality.jsonl

# Sessions with corrections
jq -s '[.[] | select(.corrections > 0)] | length' ~/.claude/metrics/session-quality.jsonl

# Most complex sessions
jq -s 'sort_by(-.tool_calls) | .[:5] | .[] | "\(.tool_calls) tools, \(.corrections) corrections — \(.cwd)"' ~/.claude/metrics/session-quality.jsonl
```
