#!/usr/bin/env bash
# strip-cmd.sh — Shared utility sourced by hooks. Provides strip_cmd() which
# replaces heredoc bodies and -m/--message argument contents with placeholders,
# so downstream pattern-matching doesn't fire on commit-message text.
#
# Usage in a hook:
#   source "$(dirname "$0")/../_lib/strip-cmd.sh"
#   CMD_STRIPPED=$(strip_cmd "$CMD")
#   echo "$CMD_STRIPPED" | grep -qE '<dangerous-pattern>'

# see: README.md § strip-cmd.sh — why the marker-line class excludes command boundaries
strip_cmd() {
  # No perl: return the command UNCHANGED (over-fire), never empty, which would silently disable every caller.
  if ! command -v perl >/dev/null 2>&1; then
    printf '%s' "$1"
    return
  fi
  printf '%s' "$1" | perl -0777 -pe '
    s/<<-?["\x27]?([A-Za-z_][A-Za-z0-9_]*)["\x27]?[^\n;&|(`]*\n.*?\n[ \t]*\1\b/<<STRIPPED_HEREDOC>>/gs;
    s/(-m|--message)([ =]+)"((?:\\.|[^"\\])*)"/\1\2"STRIPPED_MSG"/g;
    s/(-m|--message)([ =]+)\x27[^\x27]*\x27/\1\2\x27STRIPPED_MSG\x27/g;
  '
}

# strip_quoted_args() — blank quoted literals so an INVOCATION detector cannot fire on the same words as data.
# see: tools/claude/examples/hooks/_lib/README.md § strip-quoted-args.pl — what survives blanking, and when NOT to use this
strip_quoted_args() {
  local helper
  helper="$(dirname "${BASH_SOURCE[0]}")/strip-quoted-args.pl"
  # Unreadable helper passes the command through UNCHANGED — over-firing beats going quiet.
  if [ -r "$helper" ]; then
    printf '%s' "$1" | perl "$helper"
  else
    printf '%s' "$1"
  fi
}
