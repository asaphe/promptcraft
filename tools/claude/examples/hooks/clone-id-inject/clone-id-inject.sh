#!/usr/bin/env bash
# Clone ID injection — tells the model which repo clone/worktree it's in.
# Fires on UserPromptSubmit. Adds ~50 chars of context per turn.
#
# Register in settings.json:
# "UserPromptSubmit": [{ "matcher": "", "hooks": [{ "type": "command", "command": "/path/to/clone-id-inject.sh" }] }]
#
# Customize: Change the case pattern to match your clone naming convention.

DIR=$(basename "$PWD")

# Only inject for known multi-clone directories
# Customize this pattern for your setup:
#   myproject|myproject-[0-9]*  — for numbered clones
#   feature-*                   — for worktree branches
case "$DIR" in
  myproject|myproject-[0-9]|myproject-[0-9][0-9])
    jq -n --arg ctx "Working directory: $DIR clone ($PWD)" '{
      "hookSpecificOutput": {
        "hookEventName": "UserPromptSubmit",
        "additionalContext": $ctx
      }
    }'
    ;;
  *)
    exit 0
    ;;
esac
