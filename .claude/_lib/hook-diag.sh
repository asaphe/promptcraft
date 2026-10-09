#!/usr/bin/env bash
HOOK_DIAG_LOG="${HOOK_DIAG_LOG:-/tmp/claude-hook-diag.log}"
HOOK_DIAG_ALLOW_LOG="${HOOK_DIAG_ALLOW_LOG:-${HOME}/.claude/local/hook-allow-decisions.log}"
HOOK_DIAG_ASK_LOG="${HOOK_DIAG_ASK_LOG:-${HOME}/.claude/local/hook-ask-decisions.log}"
HOOK_DIAG_MAX_SIZE=1048576

_hook_diag_name="${HOOK_DIAG_NAME:-$(basename "$0")}"
case "$_hook_diag_name" in
  destructive-guard|worktree-preflight|skill-arg-substitution-guard|session-log|commit-attribution-guard) ;;
  *) _hook_diag_name=unknown ;;
esac

_hook_diag_rotate() {
  local log="$1" size=0
  if [ -f "$log" ]; then
    size=$(wc -c < "$log" 2>/dev/null | tr -d ' ')
    case "$size" in ''|*[!0-9]*) size=0 ;; esac
    [ "$size" -le "$HOOK_DIAG_MAX_SIZE" ] || mv "$log" "${log}.prev"
  fi
}

_hook_diag_decision() {
  case "$1" in
    none|allow|ask|deny|defer|notify|unknown) printf '%s' "$1" ;;
    *) printf unknown ;;
  esac
}

_hook_diag_write() {
  (
    local log="$1" code="$2" event="$3" decision
    case "$event" in
      exit|lost_stderr_on_exit_0|invalid_json|splitter_missing|transcript_unreadable|derive_script_missing|derive_produced_nothing|derive_returned_no_path|prune_failed|unknown) ;;
      *) event=unknown ;;
    esac
    decision=$(_hook_diag_decision "${HOOK_DIAG_DECISION:-none}")
    umask 077
    [ -e "$log" ] || : >> "$log" || exit 0
    _hook_diag_rotate "$log" || exit 0
    printf '{"ts":"%s","hook":"%s","exit":%s,"decision":"%s","event":"%s"}\n' \
      "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$_hook_diag_name" "$code" "$decision" "$event" >> "$log"
  ) 2>/dev/null || :
}

hook_diag_event() {
  _hook_diag_write "$HOOK_DIAG_LOG" null "${1:-unknown}"
}

_hook_diag_on_exit() {
  local exit_code=$?
  if [ "$exit_code" -ne 0 ]; then
    _hook_diag_write "$HOOK_DIAG_LOG" "$exit_code" exit
  elif [ -n "${HOOK_DIAG_LOG_ALLOWS:-}" ]; then
    mkdir -p "$(dirname "$HOOK_DIAG_ALLOW_LOG")" 2>/dev/null || :
    _hook_diag_write "$HOOK_DIAG_ALLOW_LOG" "$exit_code" exit
  fi
  if [ "$exit_code" -eq 0 ] && [ "${HOOK_DIAG_DECISION:-}" = ask ]; then
    mkdir -p "$(dirname "$HOOK_DIAG_ASK_LOG")" 2>/dev/null || :
    _hook_diag_write "$HOOK_DIAG_ASK_LOG" "$exit_code" exit
  fi
  if [ "$exit_code" -eq 0 ] && [ -s "$_HOOK_DIAG_STDERR" ]; then
    _hook_diag_write "$HOOK_DIAG_LOG" "$exit_code" lost_stderr_on_exit_0
  fi
  if [ "$exit_code" -eq 1 ] || [ "$exit_code" -eq 2 ]; then
    cat "$_HOOK_DIAG_STDERR" >&3 || :
  fi
  rm -f "$_HOOK_DIAG_STDERR" 2>/dev/null || :
  return "$exit_code"
}

if ! printf '%s' "$INPUT" | jq empty 2>/dev/null; then
  hook_diag_event invalid_json
  exit 0
fi

_HOOK_DIAG_STDERR=$(mktemp /tmp/hook-diag-stderr.XXXXXX) || return 0
trap _hook_diag_on_exit EXIT
exec 3>&2
exec 2>"$_HOOK_DIAG_STDERR"
