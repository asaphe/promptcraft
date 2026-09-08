#!/usr/bin/env bash
# Stop hook — appends what this turn did to $SESSION_LOG_DIR/<date>/<session-id>.md.

# Never blocks: a logger that can wedge a yield is worse than no logger.

# Install / environment / log format: see README.md in this directory.

# Requires: jq, python3

set -uo pipefail

INPUT=$(cat)
# shellcheck disable=SC2034  # read by the sourced hook-diag.sh
HOOK_DIAG_NAME="session-log"
# shellcheck source=/dev/null  # runtime-only source
[ -f "$(dirname "$0")/../_lib/hook-diag.sh" ] && source "$(dirname "$0")/../_lib/hook-diag.sh"

SESSION=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
TRANSCRIPT=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
[ -n "$SESSION" ] || exit 0
[ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ] || exit 0

DERIVE="$(dirname "$0")/session-log-derive.py"
[ -r "$DERIVE" ] || exit 0

SESSIONS_DIR="${SESSION_LOG_DIR:-${HOME}/.claude/session-logs}"
umask 077

RESULT=$(python3 "$DERIVE" --transcript "$TRANSCRIPT" --session "$SESSION" \
                           --sessions-dir "$SESSIONS_DIR" 2>/dev/null)
[ -n "$RESULT" ] || exit 0

LOG_PATH=$(printf '%s' "$RESULT" | jq -r '.path // empty' 2>/dev/null)
[ -n "$LOG_PATH" ] || exit 0

# Keyed on a marker beside the log, not a date check, so retention cannot silently never run.
PRUNED="${LOG_PATH%.md}.pruned"

# This rm runs unattended: fenced to a path this hook owns and to date-named dirs only.
case "$SESSIONS_DIR" in
  */session-logs) PRUNE_OK=1 ;;
  *) PRUNE_OK=0 ;;
esac
if [ ! -f "$PRUNED" ] && [ "$PRUNE_OK" -eq 1 ]; then
  find "$SESSIONS_DIR" -mindepth 1 -maxdepth 1 -type d -name '20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]' \
       -mtime "+${SESSION_LOG_RETENTION_DAYS:-90}" -exec rm -rf {} + 2>/dev/null
  : > "$PRUNED"
fi

ASKS=$(printf '%s' "$RESULT" | jq -r '.asks_total // 0' 2>/dev/null)
TURNS=$(printf '%s' "$RESULT" | jq -r '.state_turns // "none"' 2>/dev/null)
MINS=$(printf '%s' "$RESULT" | jq -r '.state_mins // 0' 2>/dev/null)
case "$ASKS" in ''|*[!0-9]*) ASKS=0 ;; esac
case "$MINS" in ''|*[!0-9]*) MINS=0 ;; esac

# Below five asks there is nothing worth narrating, and the nudge would fire on every short session.
[ "$ASKS" -ge 5 ] || exit 0

STALE=0
if [ "$TURNS" = "none" ] || [ "$TURNS" = "null" ]; then
  STALE=1
else
  case "$TURNS" in ''|*[!0-9]*) TURNS=0 ;; esac
  { [ "$TURNS" -ge 20 ] || [ "$MINS" -ge 45 ]; } && STALE=1
fi
[ "$STALE" -eq 1 ] || exit 0

# shellcheck disable=SC2034  # read by the sourced hook-diag.sh
HOOK_DIAG_DECISION="notify:session-log"
jq -n --arg p "$LOG_PATH" \
  '{systemMessage:("Session log has no recent state entry. Append one line to " + $p + " :  - HH:MM state · objective … | decided … | open … | next …")}'
exit 0
