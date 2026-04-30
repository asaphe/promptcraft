#!/usr/bin/env bash
# Model recommendation hook — warns when the current model doesn't match
# the recommended model for the active phase/task.
#
# Fires on UserPromptSubmit. Reads current model from the transcript JSONL
# (last assistant turn), matches user prompt against phase patterns in
# model-recommendation.json, and warns if mismatched.
#
# Exit codes: 0 = pass (with optional warning in additionalContext)
# Never blocks (exit 2) — advisory only.

set -euo pipefail

HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG="${HOOK_DIR}/model-recommendation.json"
INPUT=$(cat)

[ -f "$CONFIG" ] || exit 0

TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path // empty')
PROMPT=$(echo "$INPUT" | jq -r '.prompt // empty')

# Detect current model from the last assistant turn in the transcript.
CURRENT_MODEL=""
if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
  CURRENT_MODEL=$(tail -n 200 "$TRANSCRIPT" 2>/dev/null \
    | grep -o '"model":"[^"]*"' \
    | tail -1 \
    | sed 's/"model":"//;s/"//' \
    || true)
fi

normalize_model() {
  local m="$1"
  case "$m" in
    *opus*)   echo "opus" ;;
    *sonnet*) echo "sonnet" ;;
    *haiku*)  echo "haiku" ;;
    *)        echo "unknown" ;;
  esac
}

CURRENT=$(normalize_model "$CURRENT_MODEL")
[ "$CURRENT" = "unknown" ] && exit 0

# Match prompt against phase patterns (first match wins).
RECOMMENDED=""
NOTE=""
MATCH_COUNT=$(jq '.phases | length' "$CONFIG")

for i in $(seq 0 $(( MATCH_COUNT - 1 ))); do
  PATTERN=$(jq -r ".phases[$i].pattern" "$CONFIG")
  if echo "$PROMPT" | grep -qiE "$PATTERN" 2>/dev/null; then
    RECOMMENDED=$(jq -r ".phases[$i].model" "$CONFIG")
    NOTE=$(jq -r ".phases[$i].note" "$CONFIG")
    break
  fi
done

[ -z "$RECOMMENDED" ] && exit 0
[ "$CURRENT" = "$RECOMMENDED" ] && exit 0

jq -n --arg ctx "Model mismatch: current=$CURRENT, recommended=$RECOMMENDED for this task. $NOTE. Switch with /model $RECOMMENDED if appropriate." '{
  "hookSpecificOutput": {
    "hookEventName": "UserPromptSubmit",
    "additionalContext": $ctx
  }
}'
