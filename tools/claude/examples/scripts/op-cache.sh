#!/usr/bin/env bash
# op-cache.sh — Cache 1Password `op read` values per session to avoid repeated
# biometric prompts. Convention: never call `op read` more than once per secret
# per session. This script enforces that mechanically.
#
# Usage (drop-in replacement for `op read`):
#   value=$(~/.claude/scripts/op-cache.sh op://Vault/Item/field)
#   value=$(~/.claude/scripts/op-cache.sh "op://Vault/Item with spaces/field")
#
# Cache lives in /tmp/op-cache-<session>/ with mode 600 per file.
# Session is identified by CLAUDE_SESSION_ID env var if set, else by parent PID.
# Cleared automatically when /tmp is purged on reboot, OR by the paired
# op-cache-cleanup Stop hook.
#
# To force a fresh read (e.g., secret rotated mid-session):
#   ~/.claude/scripts/op-cache.sh --refresh op://Vault/Item/field

set -euo pipefail

REFRESH=0
if [ "${1:-}" = "--refresh" ]; then
  REFRESH=1
  shift
fi

URI="${1:-}"
if [ -z "$URI" ]; then
  echo "usage: op-cache.sh [--refresh] op://Vault/Item/field" >&2
  exit 64
fi

if [[ ! "$URI" =~ ^op:// ]]; then
  echo "op-cache.sh: argument must start with op://" >&2
  exit 64
fi

SESSION_ID="${CLAUDE_SESSION_ID:-pid-${PPID}}"
CACHE_DIR="/tmp/op-cache-${SESSION_ID}"
mkdir -p "$CACHE_DIR"
chmod 700 "$CACHE_DIR"

KEY=$(printf '%s' "$URI" | shasum -a 256 | awk '{print $1}')
CACHE_FILE="${CACHE_DIR}/${KEY}"

if [ "$REFRESH" -eq 0 ] && [ -s "$CACHE_FILE" ]; then
  cat "$CACHE_FILE"
  exit 0
fi

set +e
VALUE=$(op read "$URI")
RC=$?
set -e
if [ "$RC" -ne 0 ] || [ -z "$VALUE" ]; then
  exit "$RC"
fi

umask 077
printf '%s' "$VALUE" > "$CACHE_FILE"
printf '%s' "$VALUE"
