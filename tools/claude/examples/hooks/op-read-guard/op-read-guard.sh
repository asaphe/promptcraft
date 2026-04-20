#!/usr/bin/env bash
# 1Password duplicate read guard — blocks repeated `op read` or `op item get`
# calls for the same secret within a session.
# Each op read triggers a biometric prompt — duplicates waste user time.
#
# Register in settings.json:
# "PreToolUse": [{ "matcher": "Bash", "hooks": [{ "type": "command", "command": "/path/to/op-read-guard.sh" }] }]

INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

if [ -z "$CMD" ]; then
  exit 0
fi

# Only match op read or op item get commands
if ! echo "$CMD" | grep -qE 'op (read|item get) '; then
  exit 0
fi

# Extract the secret reference
# op read "op://vault/item/field"
SECRET_REF=$(echo "$CMD" | grep -oE 'op://[^ "'"'"']+' | head -1)
if [ -z "$SECRET_REF" ]; then
  # op item get 'item' --fields 'field'
  SECRET_REF=$(echo "$CMD" | grep -oE "op item get ['\"]?[^'\"]+['\"]?" | head -1)
fi

if [ -z "$SECRET_REF" ]; then
  exit 0
fi

# Track reads in a session-scoped file.
# CLAUDE_SESSION_ID is set by Claude Code for each session.
# Important: Do NOT use $$ (PID) — each hook invocation is a new process with a different PID.
TRACK_FILE="/tmp/claude-op-reads-${CLAUDE_SESSION_ID:-shared}"

# Check if this secret was already read
if [ -f "$TRACK_FILE" ] && grep -qF "$SECRET_REF" "$TRACK_FILE"; then
  jq -n --arg ref "$SECRET_REF" '{
    "hookSpecificOutput": {
      "hookEventName": "PreToolUse",
      "permissionDecision": "block",
      "permissionDecisionReason": ("Duplicate op read for " + $ref + ". You already read this secret earlier in this session. Reuse the value you got before — each op read triggers a biometric prompt.")
    }
  }'
  exit 0
fi

# Record this read
echo "$SECRET_REF" >> "$TRACK_FILE"
exit 0
