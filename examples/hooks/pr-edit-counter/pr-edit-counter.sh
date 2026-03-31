#!/usr/bin/env bash
# PR edit counter — warns after 2+ body edits on the same PR.
# Encourages drafting the full PR body before posting.
#
# Register in settings.json:
# "PreToolUse": [{ "matcher": "Bash", "hooks": [{ "type": "command", "command": "/path/to/pr-edit-counter.sh" }] }]

INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

if [ -z "$CMD" ]; then
  exit 0
fi

# Only match gh pr edit with --body
if ! echo "$CMD" | grep -qE 'gh +pr +edit +.*--body'; then
  exit 0
fi

# Extract PR number from the command (gh pr edit <number> --body ...)
PR_NUM=$(echo "$CMD" | grep -oE 'gh +pr +edit +([0-9]+)' | grep -oE '[0-9]+')
if [ -z "$PR_NUM" ]; then
  PR_NUM="current"
fi

COUNTER_FILE="/tmp/claude-pr-edit-count-${PR_NUM}"

# Read current count
if [ -f "$COUNTER_FILE" ]; then
  COUNT=$(cat "$COUNTER_FILE")
else
  COUNT=0
fi

# Increment
COUNT=$((COUNT + 1))
echo "$COUNT" > "$COUNTER_FILE"

# Warn after 2nd edit (allow, but with warning)
if [ "$COUNT" -gt 2 ]; then
  REASON="This is body edit #${COUNT} on PR #${PR_NUM}. Consider drafting the full PR body locally before posting — each edit rewrites the entire body. Proceeding anyway."
  jq -n \
    --arg reason "$REASON" \
    '{
      "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "allow",
        "permissionDecisionReason": $reason
      }
    }'
  exit 0
fi

# Under threshold — allow silently
exit 0
