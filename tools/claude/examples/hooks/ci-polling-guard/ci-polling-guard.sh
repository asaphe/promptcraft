#!/usr/bin/env bash
# CI polling guard — blocks sleep-based CI polling loops.
# Suggests `gh run watch` with run_in_background instead.
#
# Register in settings.json:
# "PreToolUse": [{ "matcher": "Bash", "hooks": [{ "type": "command", "command": "/path/to/ci-polling-guard.sh" }] }]

INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

if [ -z "$CMD" ]; then
  exit 0
fi

# Detect sleep followed by gh run view / gh pr checks patterns
# Common patterns:
#   sleep 30 && gh run view ...
#   sleep 30; gh run view ...
if echo "$CMD" | grep -qE 'sleep [0-9]+.*gh (run view|pr checks)'; then
  jq -n '{
    "hookSpecificOutput": {
      "hookEventName": "PreToolUse",
      "permissionDecision": "block",
      "permissionDecisionReason": "CI polling loop detected. Use `gh run watch <run-id> --exit-status` with `run_in_background: true` instead of sleep+poll. You will be notified when it completes."
    }
  }'
  exit 0
fi

# Detect bare sleep commands >= 10 seconds (likely CI waits)
if echo "$CMD" | grep -qE '^[[:space:]]*sleep [1-9][0-9]+[[:space:]]*$'; then
  jq -n '{
    "hookSpecificOutput": {
      "hookEventName": "PreToolUse",
      "permissionDecision": "block",
      "permissionDecisionReason": "Bare sleep detected (likely CI polling). Use `run_in_background: true` with the monitoring command instead of sleeping."
    }
  }'
  exit 0
fi

exit 0
