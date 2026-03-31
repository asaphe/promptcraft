#!/usr/bin/env bash
# AWS auth check — validates SSO sessions at session start and injects profile context.
# Eliminates repeated `export AWS_PROFILE=X &&` boilerplate on every command.
#
# Register in settings.json:
# "UserPromptSubmit": [{ "matcher": "", "hooks": [{ "type": "command", "command": "/path/to/aws-auth-check.sh" }] }]
#
# Customize: Change profile names, add/remove profiles, adjust cache TTL.

CACHE_FILE="/tmp/claude-aws-auth-${CLAUDE_SESSION_ID:-shared}"
CACHE_TTL=300  # 5 minutes

# Check if cache is fresh
if [ -f "$CACHE_FILE" ]; then
  CACHE_AGE=$(( $(date +%s) - $(stat -f %m "$CACHE_FILE" 2>/dev/null || echo 0) ))
  if [ "$CACHE_AGE" -lt "$CACHE_TTL" ]; then
    cat "$CACHE_FILE"
    exit 0
  fi
fi

check_profile() {
  local profile="$1"
  if aws sts get-caller-identity --profile "$profile" &>/dev/null; then
    echo "valid"
  else
    echo "expired"
  fi
}

# Customize: Add your AWS profiles here
PROD_STATUS=$(check_profile "prod")
DEV_STATUS=$(check_profile "dev")

CONTEXT="AWS SSO: prod=$PROD_STATUS, dev=$DEV_STATUS."
if [ "$PROD_STATUS" = "valid" ]; then
  CONTEXT="$CONTEXT Use AWS_PROFILE=prod (active, no re-export needed per-command)."
fi
if [ "$PROD_STATUS" = "expired" ]; then
  CONTEXT="$CONTEXT prod expired — prompt user: ! aws sso login --profile prod"
fi
if [ "$DEV_STATUS" = "expired" ]; then
  CONTEXT="$CONTEXT dev expired — prompt user if dev access needed."
fi

OUTPUT=$(jq -n --arg ctx "$CONTEXT" '{
  "hookSpecificOutput": {
    "hookEventName": "UserPromptSubmit",
    "additionalContext": $ctx
  }
}')

echo "$OUTPUT" | tee "$CACHE_FILE"
