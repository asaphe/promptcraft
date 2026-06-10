#!/usr/bin/env bash
set -euo pipefail

# SessionStart hook: check for pending learnings from previous sessions
# and nudge about auto-memory if MEMORY.md is empty.
#
# Output on stdout is injected into Claude's context (SessionStart behavior).
# Input: JSON on stdin with transcript_path, session_id, cwd, source.
# Stdin is small hook metadata JSON (not the full transcript) — safe to buffer.

command -v jq &>/dev/null || exit 0

INPUT=$(cat)
TRANSCRIPT_PATH=$(printf '%s\n' "$INPUT" | jq -r '.transcript_path // empty')

if [[ -z "$TRANSCRIPT_PATH" ]]; then
  exit 0
fi

PROJECT_DIR=$(dirname "$TRANSCRIPT_PATH")
while [[ ! -d "$PROJECT_DIR/memory" && "$PROJECT_DIR" == *".claude/projects"* ]]; do
  PROJECT_DIR=$(dirname "$PROJECT_DIR")
done

MEMORY_DIR="$PROJECT_DIR/memory"
PENDING_FILE="$MEMORY_DIR/pending-learnings.md"
MEMORY_FILE="$MEMORY_DIR/MEMORY.md"

OUTPUT=""

# Check for pending learnings
if [[ -f "$PENDING_FILE" && -s "$PENDING_FILE" ]]; then
  CANDIDATE_COUNT=$(grep -cE '^## (Session|Pre-compaction)' "$PENDING_FILE" 2>/dev/null || echo "0")
  if [[ "$CANDIDATE_COUNT" -gt 0 ]]; then
    # Check age of oldest entry for urgency
    OLDEST_DATE=$(grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' "$PENDING_FILE" 2>/dev/null | head -1 || true)
    AGE_NOTE=""
    if [[ -n "$OLDEST_DATE" ]]; then
      # Portable date parsing: macOS uses -j -f, Linux uses -d
      if date -j -f "%Y-%m-%d" "$OLDEST_DATE" "+%s" >/dev/null 2>&1; then
        OLDEST_TS=$(date -j -f "%Y-%m-%d" "$OLDEST_DATE" "+%s")
      elif date -d "$OLDEST_DATE" "+%s" >/dev/null 2>&1; then
        OLDEST_TS=$(date -d "$OLDEST_DATE" "+%s")
      else
        OLDEST_TS=0
      fi
      NOW_TS=$(date "+%s")
      AGE_DAYS=$(( (NOW_TS - OLDEST_TS) / 86400 ))
      if [[ "$AGE_DAYS" -ge 3 ]]; then
        AGE_NOTE=" Oldest entry is ${AGE_DAYS} days old — corrections are being lost."
      fi
    fi
    if [[ "$CANDIDATE_COUNT" -ge 5 ]]; then
      OUTPUT+="[Learning System] PRIORITY: $CANDIDATE_COUNT pending learning candidate(s) from previous sessions.${AGE_NOTE}"
    else
      OUTPUT+="[Learning System] $CANDIDATE_COUNT pending learning candidate(s) from previous sessions.${AGE_NOTE}"
    fi
    OUTPUT+=" File: $PENDING_FILE"
    OUTPUT+=" When appropriate during this session, read the file and propose rules for any valid patterns."
    OUTPUT+=" After processing, clear the file. Classify: team-wide → .claude/rules/, agent-specific → .claude/agents/\${agent}.md, personal → auto memory."
  fi
fi

# Nudge about auto-memory if MEMORY.md is empty or missing.
if true; then
  if [[ ! -f "$MEMORY_FILE" || ! -s "$MEMORY_FILE" ]]; then
    if [[ -n "$OUTPUT" ]]; then
      OUTPUT+=" | "
    fi
    OUTPUT+="[Auto Memory] Your personal project memory (MEMORY.md) is empty."
    OUTPUT+=" Use it for personal preferences and debugging insights that don't belong in shared .claude/rules/."
    OUTPUT+=" Tell Claude 'remember that...' to save personal learnings."
  fi
fi

if [[ -n "$OUTPUT" ]]; then
  echo "$OUTPUT"
fi

exit 0
