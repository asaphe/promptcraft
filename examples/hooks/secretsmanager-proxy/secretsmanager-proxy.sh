#!/usr/bin/env bash
# Token proxy for secret value commands — auto-wraps commands that return
# large JSON payloads with a token-optimization proxy to prevent truncation.
#
# This solves a specific problem: when using a token-optimization tool (like RTK)
# that filters/summarizes CLI output, JSON secret values get truncated.
# The proxy bypasses filtering for these specific commands.
#
# Register in settings.json:
# "PreToolUse": [{ "matcher": "Bash", "hooks": [{ "type": "command", "command": "/path/to/secretsmanager-proxy.sh" }] }]
#
# Customize: Change the command patterns and proxy command to match your setup.

PROXY_CMD="rtk proxy"  # Change to your token proxy bypass command

INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

if [ -z "$CMD" ]; then
  exit 0
fi

# Match commands that return large JSON and shouldn't be filtered
# Customize these patterns for your workflow
if ! echo "$CMD" | grep -qE 'aws secretsmanager (get-secret-value|batch-get-secret-value)'; then
  exit 0
fi

# Already using the proxy — no rewrite needed
if echo "$CMD" | grep -qF "$PROXY_CMD"; then
  exit 0
fi

# Strip any existing proxy prefix (in case of double-rewrite), then wrap
CLEAN_CMD="${CMD//$PROXY_CMD /}"
REWRITTEN="$PROXY_CMD $CLEAN_CMD"

ORIGINAL_INPUT=$(echo "$INPUT" | jq -c '.tool_input')
UPDATED_INPUT=$(echo "$ORIGINAL_INPUT" | jq --arg cmd "$REWRITTEN" '.command = $cmd')

jq -n \
  --argjson updated "$UPDATED_INPUT" \
  '{
    "hookSpecificOutput": {
      "hookEventName": "PreToolUse",
      "permissionDecision": "allow",
      "permissionDecisionReason": "Auto-proxied to prevent token-optimization truncation of JSON output",
      "updatedInput": $updated
    }
  }'
