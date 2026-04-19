#!/usr/bin/env bash
# Session quality capture — Stop hook that records session metrics.
# Runs when a Claude Code session ends. Writes to ~/.claude/metrics/session-quality.jsonl
#
# Metrics captured:
# - session_id, timestamp, working_directory
# - tool_call_count (from session JSONL)
# - correction_count (user frustration/correction patterns)
# - pr_edit_counts (from /tmp/claude-pr-edit-count-*)
# - cost_usd (from session-cost.py — ~/.claude/scripts/ or alongside this script)
#
# Register in settings.json:
# "Stop": [{ "matcher": "", "hooks": [{ "type": "command", "command": "/path/to/session-quality-capture.sh" }] }]

INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "unknown"')
CWD=$(echo "$INPUT" | jq -r '.cwd // "unknown"')
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

METRICS_DIR="$HOME/.claude/metrics"
METRICS_FILE="$METRICS_DIR/session-quality.jsonl"
mkdir -p "$METRICS_DIR"

# Count PR edit counter files (from pr-edit-counter.sh companion hook)
PR_EDITS=0
for f in /tmp/claude-pr-edit-count-*; do
  if [ -f "$f" ]; then
    COUNT=$(cat "$f" 2>/dev/null || echo 0)
    PR_EDITS=$((PR_EDITS + COUNT))
    rm -f "$f"
  fi
done

# Find the session JSONL file
SESSION_FILE=""
for proj_dir in "$HOME"/.claude/projects/*/; do
  candidate="${proj_dir}${SESSION_ID}.jsonl"
  if [ -f "$candidate" ]; then
    SESSION_FILE="$candidate"
    break
  fi
done

TOOL_CALLS=0
CORRECTIONS=0
COST_USD=0

if [ -n "$SESSION_FILE" ] && [ -f "$SESSION_FILE" ]; then
  # Count tool calls (assistant messages with tool_use content blocks)
  TOOL_CALLS=$(jq -r 'select(.type == "assistant") | .message.content[]? | select(.type == "tool_use") | .name' "$SESSION_FILE" 2>/dev/null | wc -l | tr -d ' ')

  # Count corrections (user messages with frustration/correction markers)
  CORRECTIONS=$(jq -r 'select(.type == "user") | .message.content | if type == "string" then . elif type == "array" then map(select(.type == "text") | .text) | join("\n") else empty end' "$SESSION_FILE" 2>/dev/null | grep -ciE 'no[, !.].*wrong|stop doing|not that|I said|don.t do|shouldn.t|why did you' || echo 0)

  # Calculate cost via session-cost.py; check ~/.claude/scripts/ then alongside this script
  COST_SCRIPT="$HOME/.claude/scripts/session-cost.py"
  [ -f "$COST_SCRIPT" ] || COST_SCRIPT="$(cd "$(dirname "$0")" && pwd)/session-cost.py"
  if [ -f "$COST_SCRIPT" ]; then
    COST_JSON=$(python3 "$COST_SCRIPT" "$SESSION_FILE" --json 2>/dev/null | tail -1)
    COST_USD=$(echo "$COST_JSON" | jq -r '.total_cost // 0' 2>/dev/null || echo 0)
    [ -n "$COST_USD" ] || COST_USD=0
    printf 'Session cost: $%.4f\n' "$COST_USD" >&2
  fi
fi

# Write metrics line
jq -n \
  --arg sid "$SESSION_ID" \
  --arg ts "$TIMESTAMP" \
  --arg cwd "$CWD" \
  --argjson tools "${TOOL_CALLS:-0}" \
  --argjson corrections "${CORRECTIONS:-0}" \
  --argjson pr_edits "$PR_EDITS" \
  --argjson cost "${COST_USD:-0}" \
  '{
    session_id: $sid,
    timestamp: $ts,
    cwd: $cwd,
    tool_calls: $tools,
    corrections: $corrections,
    pr_body_edits: $pr_edits,
    cost_usd: $cost
  }' >> "$METRICS_FILE"

exit 0
