#!/usr/bin/env bash
# Shared learn-candidate detection library — variables and functions only, no side effects on source.
# See: ../../../guides/learning-system-guide.md § Automated Candidate Detection (consumers, thresholds, rationale).

# Tunables — override via environment before sourcing.
export LEARN_CORRECTION_MIN="${LEARN_CORRECTION_MIN:-2}"   # correction matches needed to flag a session
export LEARN_TOOL_FAIL_MIN="${LEARN_TOOL_FAIL_MIN:-6}"     # absolute floor of failed tool calls
export LEARN_TOOL_FAIL_RATE="${LEARN_TOOL_FAIL_RATE:-25}"  # minimum failure percentage

# User pushback phrasing — 2+ matches per session indicates a recurring blind spot, not a routine "no".
export LEARN_CORRECTION_PATTERN='(no[, !.].*(wrong|that|don.t|stop)|stop doing|not that|I (said|told)|why (did|are) you|shouldn.t|don.t (do|assume)|you assumed|you guessed|did you (actually|even)|wait.*didn.t)'

# Explicit codification requests — a single match is enough, the user asked.
export LEARN_LEARN_PATTERN='(remember this|codify this|add (to|this).*(rule|claude)|keep happening|every (session|time)|let.s codify|always do|put this in|new rule)'

# Count all tool results in a transcript ($1 = path) — tool results arrive as user-role messages with array content.
learn_total_tools() {
  jq -r 'select(.type=="user") | .message.content | (if type=="array" then . else [] end) | map(select(.type=="tool_result")) | length' "$1" 2>/dev/null | awk '{s+=$1} END {print s+0}'
}

# Count failed tool results, is_error==true ($1 = path).
learn_failed_tools() {
  jq -r 'select(.type=="user") | .message.content | (if type=="array" then . else [] end) | map(select(.type=="tool_result" and .is_error==true)) | length' "$1" 2>/dev/null | awk '{s+=$1} END {print s+0}'
}

# Human-typed text only ($1 = path) — drop tool results so correction regexes never match tool output.
learn_user_text() {
  jq -r 'select(.type == "user") | .message.content | if type == "string" then . elif type == "array" then map(select(.type == "text") | .text) | join("\n") else empty end' "$1" 2>/dev/null
}

# Up to N sample error texts from failed tool results, one line ($1 = path, $2 = max, default 3).
learn_sample_errors() {
  jq -r 'select(.type=="user") | .message.content | (if type=="array" then . else [] end) | .[] | select(.type=="tool_result" and .is_error==true) | (.content | if type=="array" then (map(.text? // "") | join(" ")) elif type=="string" then . else "" end)' "$1" 2>/dev/null | grep -v '^[[:space:]]*$' | head -"${2:-3}" | tr '\n' ' '
}

# Evaluate one transcript ($1 = path); prints "TRIGGER TOOL_TRIGGERED CORRECTIONS LEARNS FAILED TOTAL".
learn_evaluate() {
  local f="$1" utext cc lc total failed trig=0 tooltrig=0
  utext=$(learn_user_text "$f")
  cc=$(printf '%s' "$utext" | grep -ciE "$LEARN_CORRECTION_PATTERN" || true)
  lc=$(printf '%s' "$utext" | grep -ciE "$LEARN_LEARN_PATTERN" || true)
  total=$(learn_total_tools "$f")
  failed=$(learn_failed_tools "$f")

  [ "${cc:-0}" -ge "$LEARN_CORRECTION_MIN" ] && trig=1
  [ "${lc:-0}" -ge 1 ] && trig=1
  # Dual failure gate: absolute floor filters short sessions, rate filters long ones — both must pass.
  if [ "${failed:-0}" -ge "$LEARN_TOOL_FAIL_MIN" ] && [ "${total:-0}" -gt 0 ]; then
    [ $(( failed * 100 / total )) -ge "$LEARN_TOOL_FAIL_RATE" ] && { trig=1; tooltrig=1; }
  fi
  printf '%s %s %s %s %s %s\n' "$trig" "$tooltrig" "${cc:-0}" "${lc:-0}" "${failed:-0}" "${total:-0}"
}
