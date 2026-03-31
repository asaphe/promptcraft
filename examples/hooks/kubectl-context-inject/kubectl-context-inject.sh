#!/usr/bin/env bash
# kubectl default context — rewrites kubectl/helm commands to include a default
# --context flag when none is specified. Useful when you have a single cluster
# or a known default.
#
# Register in settings.json:
# "PreToolUse": [{ "matcher": "Bash", "hooks": [{ "type": "command", "command": "/path/to/kubectl-context-inject.sh" }] }]
#
# Customize: Change DEFAULT_CONTEXT to your cluster name.

DEFAULT_CONTEXT="my-cluster"

INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

if [ -z "$CMD" ]; then
  exit 0
fi

# Only match kubectl/helm commands
if ! echo "$CMD" | grep -qE '(kubectl|helm) '; then
  exit 0
fi

# Skip if --context is already specified
if echo "$CMD" | grep -qE -- '--context[= ]'; then
  exit 0
fi

# Skip config/context management commands
if echo "$CMD" | grep -qE 'kubectl (config|cluster-info)'; then
  exit 0
fi

# Skip helm commands that don't target a cluster
if echo "$CMD" | grep -qE 'helm (repo|search|plugin|env|version|completion|create|package|template|show|pull|push|lint)'; then
  exit 0
fi

# Rewrite: insert --context after kubectl/helm
REWRITTEN=$(echo "$CMD" | sed -E "s/(kubectl|helm) /\1 --context $DEFAULT_CONTEXT /")

ORIGINAL_INPUT=$(echo "$INPUT" | jq -c '.tool_input')
UPDATED_INPUT=$(echo "$ORIGINAL_INPUT" | jq --arg cmd "$REWRITTEN" '.command = $cmd')

jq -n \
  --argjson updated "$UPDATED_INPUT" \
  --arg ctx "$DEFAULT_CONTEXT" \
  '{
    "hookSpecificOutput": {
      "hookEventName": "PreToolUse",
      "permissionDecision": "allow",
      "permissionDecisionReason": ("Auto-injected --context " + $ctx),
      "updatedInput": $updated
    }
  }'
