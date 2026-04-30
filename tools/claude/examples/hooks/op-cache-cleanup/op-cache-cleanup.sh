#!/usr/bin/env bash
# op-cache-cleanup.sh — Stop hook that purges this session's 1Password cache.
# Pairs with the op-cache.sh script (per-session cache under
# /tmp/op-cache-${CLAUDE_SESSION_ID}). Without this, cached secrets sit in
# /tmp until OS reboot.

INPUT=$(cat)
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty')

[ -n "$SESSION_ID" ] && rm -rf "/tmp/op-cache-${SESSION_ID}"

exit 0
