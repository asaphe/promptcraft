#!/usr/bin/env bash
# Diagnostic wrapper for PreToolUse:Bash hooks.
# Source this at the top of each hook AFTER reading stdin into $INPUT.
# Logs hook name, exit code, stderr, and the triggering command to a rotating log.
# Re-emits captured stderr to Claude Code on exit 1 (soft block) and exit 2 (hard
# block) so the block reason is visible to the model.

HOOK_DIAG_LOG="/tmp/claude-hook-diag.log"
HOOK_DIAG_MAX_SIZE=1048576  # 1MB, then rotate

_hook_diag_name="${HOOK_DIAG_NAME:-$(basename "$0")}"

_hook_diag_rotate() {
  if [ -f "$HOOK_DIAG_LOG" ] && [ "$(stat -f%z "$HOOK_DIAG_LOG" 2>/dev/null || echo 0)" -gt "$HOOK_DIAG_MAX_SIZE" ]; then
    mv "$HOOK_DIAG_LOG" "${HOOK_DIAG_LOG}.prev"
  fi
}

_hook_diag_on_exit() {
  local exit_code=$?
  local captured_stderr
  captured_stderr=$(cat "$_HOOK_DIAG_STDERR" 2>/dev/null)

  if [ "$exit_code" -ne 0 ]; then
    _hook_diag_rotate
    {
      echo "---"
      echo "ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
      echo "hook=$_hook_diag_name"
      echo "exit=$exit_code"
      echo "cmd=${_HOOK_DIAG_CMD:0:500}"
      [ -n "$captured_stderr" ] && echo "stderr_tail=${captured_stderr:0:200}"
    } >> "$HOOK_DIAG_LOG"
  fi

  # Re-emit captured stderr to Claude Code on exit 1 (soft block) and exit 2
  # (hard block) so the block reason is visible to the model. Without this,
  # Claude Code sees a non-zero exit with no explanation → "No stderr output".
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
  _hook_diag_rotate
  {
    echo "---"
    echo "ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "hook=$_hook_diag_name"
    echo "event=BAIL_OUT_INVALID_JSON"
    echo "input_head=${INPUT:0:200}"
  } >> "$HOOK_DIAG_LOG"
  exit 0
fi

_HOOK_DIAG_CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
_HOOK_DIAG_STDERR=$(mktemp /tmp/hook-diag-stderr.XXXXXX)

trap _hook_diag_on_exit EXIT
exec 3>&2              # save original stderr (FD 3) so we can re-emit on exit 1
exec 2>"$_HOOK_DIAG_STDERR"
