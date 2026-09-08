#!/usr/bin/env bash
# Diagnostic wrapper for PreToolUse:Bash hooks.
# Source this at the top of each hook AFTER reading stdin into $INPUT.
# Logs hook name, exit code, stderr, and the triggering command to a rotating log.
# Re-emits captured stderr on exit 1 and exit 2 so the reason reaches the model. Exit 2 is the
# only code that blocks the tool call; on exit 0 the harness discards stderr, logged here instead.
# see: tools/claude/examples/hooks/_lib/README.md § hook-diag.sh — the LOST_STDERR_ON_EXIT_0 check and the ask/allow logs

# Overridable so a test harness logs elsewhere instead of appending to the corpus it reads.
HOOK_DIAG_LOG="${HOOK_DIAG_LOG:-/tmp/claude-hook-diag.log}"
# Under $HOME, not a fixed /tmp name: these records carry raw command text, and a predictable path in a world-writable dir is a symlink target.
HOOK_DIAG_ALLOW_LOG="${HOOK_DIAG_ALLOW_LOG:-${HOME}/.claude/local/hook-allow-decisions.log}"
# Asks are the only input to prompt-volume tuning, and the allow flood would rotate them out within the hour.
HOOK_DIAG_ASK_LOG="${HOOK_DIAG_ASK_LOG:-${HOME}/.claude/local/hook-ask-decisions.log}"
HOOK_DIAG_MAX_SIZE=1048576  # 1MB, then rotate

_hook_diag_name="${HOOK_DIAG_NAME:-$(basename "$0")}"

# `wc -c`, not `stat -f%z`: the latter is BSD-only, so on Linux rotation silently never fired.
_hook_diag_rotate() {
  local log="$1" size
  size=$(wc -c < "$log" 2>/dev/null | tr -d ' ')
  case "$size" in ''|*[!0-9]*) size=0 ;; esac
  if [ -f "$log" ] && [ "$size" -gt "$HOOK_DIAG_MAX_SIZE" ]; then
    mv "$log" "${log}.prev"
  fi
}

# Records carry verbatim command text, which can include credential material.
_hook_diag_touch() {
  [ -e "$1" ] || (umask 077; : >> "$1") 2>/dev/null
}

# hook_diag_event <NAME> [detail] — record a hook's own degradation; exit 0 discards stderr, so it is otherwise unobservable.
hook_diag_event() {
  _hook_diag_touch "$HOOK_DIAG_LOG"
  _hook_diag_rotate "$HOOK_DIAG_LOG"
  {
    echo "---"
    echo "ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "hook=$_hook_diag_name"
    echo "event=$1"
    [ -n "${2:-}" ] && echo "detail=$(printf '%s' "$2" | tr '\n\r' '  ')"
  } >> "$HOOK_DIAG_LOG" 2>/dev/null
}

_hook_diag_on_exit() {
  local exit_code=$?
  local captured_stderr flat_stderr flat_decision
  captured_stderr=$(cat "$_HOOK_DIAG_STDERR" 2>/dev/null)
  # Flattened before logging: a newline in ANY field lets a body line forge a `---`/`ts=`/`hook=` record.
  flat_stderr=$(printf '%s' "$captured_stderr" | tr '\n\r' '  ')
  flat_decision=$(printf '%s' "${HOOK_DIAG_DECISION:-}" | tr '\n\r' '  ')

  if [ "$exit_code" -ne 0 ]; then
    _hook_diag_touch "$HOOK_DIAG_LOG"; _hook_diag_rotate "$HOOK_DIAG_LOG"
    {
      echo "---"
      echo "ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
      echo "hook=$_hook_diag_name"
      echo "exit=$exit_code"
      echo "cmd=${_HOOK_DIAG_CMD:0:500}"
      [ -n "$flat_stderr" ] && echo "stderr_tail=${flat_stderr:0:200}"
    } >> "$HOOK_DIAG_LOG"
  elif [ -n "${HOOK_DIAG_LOG_ALLOWS:-}" ]; then
    mkdir -p "$(dirname "$HOOK_DIAG_ALLOW_LOG")" 2>/dev/null
    _hook_diag_touch "$HOOK_DIAG_ALLOW_LOG"; _hook_diag_rotate "$HOOK_DIAG_ALLOW_LOG"
    {
      echo "---"
      echo "ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
      echo "hook=$_hook_diag_name"
      echo "exit=$exit_code"
      # An ask and a plain allow are both exit 0; without this, prompt volume is unmeasurable.
      echo "decision=${flat_decision:-allow}"
      echo "cmd=${_HOOK_DIAG_CMD:0:500}"
    } >> "$HOOK_DIAG_ALLOW_LOG"
  fi

  # Gated on exit 0: a prompt is only a prompt if the call was let through, and an inherited decision would log a block as an ask.
  if [ "$exit_code" -eq 0 ]; then
    case "$flat_decision" in
      ask*)
        mkdir -p "$(dirname "$HOOK_DIAG_ASK_LOG")" 2>/dev/null
        _hook_diag_touch "$HOOK_DIAG_ASK_LOG"; _hook_diag_rotate "$HOOK_DIAG_ASK_LOG"
        {
          echo "---"
          echo "ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
          echo "hook=$_hook_diag_name"
          echo "decision=${flat_decision}"
          echo "cmd=${_HOOK_DIAG_CMD:0:500}"
        } >> "$HOOK_DIAG_ASK_LOG"
        ;;
    esac
  fi

  # Exit 0 discards stderr outright, so a hook writing there on a pass path is talking to no one.
  if [ "$exit_code" -eq 0 ] && [ -n "$captured_stderr" ]; then
    _hook_diag_touch "$HOOK_DIAG_LOG"; _hook_diag_rotate "$HOOK_DIAG_LOG"
    {
      echo "---"
      echo "ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
      echo "hook=$_hook_diag_name"
      echo "event=LOST_STDERR_ON_EXIT_0"
      echo "stderr_head=${flat_stderr:0:200}"
      echo "cmd=${_HOOK_DIAG_CMD:0:500}"
    } >> "$HOOK_DIAG_LOG"
  fi

  # Re-emit captured stderr on exit 1 (non-blocking error — the tool still runs) and exit 2
  # (the only blocking code), so the reason is visible to the model. Without this, Claude Code
  # sees a non-zero exit with no explanation → "No stderr output".
  # Restore FD 2 to the original stderr (FD 3) first so Claude Code's pipe sees it.
  if { [ "$exit_code" -eq 1 ] || [ "$exit_code" -eq 2 ]; } && [ -n "$captured_stderr" ]; then
    exec 2>&3
    echo "$captured_stderr" >&2
  fi

  rm -f "$_HOOK_DIAG_STDERR" 2>/dev/null
}

# Bail out early if INPUT is not valid JSON — Claude Code occasionally
# sends non-JSON payloads. Since this file is sourced, exit 0 passes
# through cleanly from the host hook.
if ! echo "$INPUT" | jq empty 2>/dev/null; then
  _hook_diag_touch "$HOOK_DIAG_LOG"; _hook_diag_rotate "$HOOK_DIAG_LOG"
  {
    echo "---"
    echo "ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "hook=$_hook_diag_name"
    echo "event=BAIL_OUT_INVALID_JSON"
    echo "input_head=$(printf '%s' "${INPUT:0:200}" | tr '\n\r' '  ')"
  } >> "$HOOK_DIAG_LOG"
  exit 0
fi

_HOOK_DIAG_CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null | tr '\n\r' '  ')
_HOOK_DIAG_STDERR=$(mktemp /tmp/hook-diag-stderr.XXXXXX)

trap _hook_diag_on_exit EXIT
exec 3>&2              # save original stderr (FD 3) so we can re-emit on exit 1
exec 2>"$_HOOK_DIAG_STDERR"
