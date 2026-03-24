#!/usr/bin/env bash
set -euo pipefail

# SessionEnd hook: scan transcript for correction signals and write candidates
# to pending-learnings.md for review in the next session.
#
# Runs async — does not block session termination.
# Input: JSON on stdin with transcript_path, session_id, cwd, reason.

INPUT=$(cat)
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty')
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')

if [[ -z "$TRANSCRIPT_PATH" || ! -f "$TRANSCRIPT_PATH" ]]; then
  exit 0
fi

PROJECT_DIR=$(dirname "$TRANSCRIPT_PATH")
while [[ ! -d "$PROJECT_DIR/memory" && "$PROJECT_DIR" == *".claude/projects"* ]]; do
  PROJECT_DIR=$(dirname "$PROJECT_DIR")
done

MEMORY_DIR="$PROJECT_DIR/memory"
mkdir -p "$MEMORY_DIR"
PENDING_FILE="$MEMORY_DIR/pending-learnings.md"

# --- Signal detection ---

# 1. User corrections: "no", "wrong", "not that", "I said", "actually,"
# Minimum 30 chars to avoid false positives from short denials.
CORRECTIONS=$(jq -r '
  select(.type == "user") |
  .message.content // [] |
  if type == "array" then .[] else . end |
  if type == "object" then .text // empty else . end
' "$TRANSCRIPT_PATH" 2>/dev/null | \
  grep -iE '(^no[,. !]|wrong|not that|that.s not|I said|I meant|actually,|correction:)' | \
  grep -vE '^.{0,29}$' | \
  head -10 || true)

# 2. Retry patterns: same tool name appearing consecutively
RETRIES=$(jq -r '
  select(.type == "assistant") |
  .message.content // [] | .[] |
  select(.type == "tool_use") |
  .name
' "$TRANSCRIPT_PATH" 2>/dev/null | \
  uniq -d | head -5 || true)

# 3. Session length (tool call count)
TOOL_COUNT=$(jq -r '
  select(.type == "assistant") |
  .message.content // [] | .[] |
  select(.type == "tool_use") |
  .name
' "$TRANSCRIPT_PATH" 2>/dev/null | wc -l | tr -d ' ' || true)
TOOL_COUNT=${TOOL_COUNT:-0}

# --- Evaluate signals ---

CORRECTION_COUNT=$(echo "$CORRECTIONS" | grep -c '.' 2>/dev/null || true)
RETRY_COUNT=$(echo "$RETRIES" | grep -c '.' 2>/dev/null || true)
TOTAL_SIGNALS=$((CORRECTION_COUNT + RETRY_COUNT))

# Only write if meaningful signals found
if [[ "$TOTAL_SIGNALS" -lt 2 && "$TOOL_COUNT" -lt 50 ]]; then
  exit 0
fi

# --- Write candidates ---

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

{
  echo ""
  echo "## Session $SESSION_ID ($TIMESTAMP)"
  echo ""
  echo "- **Working directory:** $CWD"
  echo "- **Tool calls:** $TOOL_COUNT"
  echo "- **Corrections detected:** $CORRECTION_COUNT"
  echo "- **Retry patterns:** $RETRY_COUNT"
  echo ""

  if [[ "$CORRECTION_COUNT" -gt 0 ]]; then
    echo "### Correction signals"
    echo ""
    echo '```'
    echo "$CORRECTIONS"
    echo '```'
    echo ""
  fi

  if [[ "$RETRY_COUNT" -gt 0 ]]; then
    echo "### Retry patterns (same tool called repeatedly)"
    echo ""
    echo '```'
    echo "$RETRIES"
    echo '```'
    echo ""
  fi

  if [[ "$TOOL_COUNT" -ge 50 ]]; then
    echo "### Long session flag"
    echo ""
    echo "Session had $TOOL_COUNT tool calls — may indicate complexity or confusion."
    echo ""
  fi

  echo "---"
} >> "$PENDING_FILE"

exit 0
