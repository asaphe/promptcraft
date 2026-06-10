#!/usr/bin/env bash
set -euo pipefail

# PreCompact hook: preserve correction context before compaction loses it.
#
# Runs before context compaction. Scans the current transcript for corrections
# that haven't been captured as rules yet, and appends them to pending-learnings.md.
# Cannot block compaction — used for side effects only.
#
# Input: JSON on stdin with transcript_path, session_id, cwd, trigger, custom_instructions.
# Stdin is small hook metadata JSON (not the full transcript) — safe to buffer.

command -v jq &>/dev/null || exit 0

INPUT=$(cat)
TRANSCRIPT_PATH=$(printf '%s\n' "$INPUT" | jq -r '.transcript_path // empty')
SESSION_ID=$(printf '%s\n' "$INPUT" | jq -r '.session_id // empty')
CWD=$(printf '%s\n' "$INPUT" | jq -r '.cwd // empty')
TRIGGER=$(printf '%s\n' "$INPUT" | jq -r '.trigger // "unknown"')

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

# Extract recent corrections (last 200 lines of transcript to avoid scanning huge files)
CORRECTIONS=$(tail -200 "$TRANSCRIPT_PATH" | jq -r '
  select(.type == "user") |
  .message.content // [] |
  if type == "array" then .[] else . end |
  if type == "object" then .text // empty else . end
' 2>/dev/null | \
  grep -iE '(^no[,. !]|wrong|not that|that.s not|I said|I meant|actually,|correction:)' | \
  grep -vE '^.{0,29}$' | \
  head -5 || true)

CORRECTION_COUNT=$(echo "$CORRECTIONS" | grep -c '.' 2>/dev/null || true)

if [[ "$CORRECTION_COUNT" -lt 1 ]]; then
  exit 0
fi

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

{
  echo ""
  echo "## Pre-compaction snapshot ($TIMESTAMP, trigger: $TRIGGER)"
  echo ""
  echo "- **Session:** $SESSION_ID"
  echo "- **Working directory:** $CWD"
  echo "- **Corrections in recent context:** $CORRECTION_COUNT"
  echo ""
  echo "### Correction signals (pre-compaction)"
  echo ""
  echo '```'
  echo "$CORRECTIONS"
  echo '```'
  echo ""
  echo "---"
} >> "$PENDING_FILE"

exit 0
