#!/usr/bin/env bash
# strip-cmd.sh — Shared utility sourced by hooks. Provides strip_cmd() which
# replaces heredoc bodies and -m/--message argument contents with placeholders,
# so downstream pattern-matching doesn't fire on commit-message text.
#
# Usage in a hook:
#   source "$(dirname "$0")/../_lib/strip-cmd.sh"
#   CMD_STRIPPED=$(strip_cmd "$CMD")
#   echo "$CMD_STRIPPED" | grep -qE '<dangerous-pattern>'

strip_cmd() {
  printf '%s' "$1" | perl -0777 -pe '
    s/<<-?["\x27]?([A-Za-z_][A-Za-z0-9_]*)["\x27]?\s*\n.*?\n[ \t]*\1\b/<<STRIPPED_HEREDOC>>/gs;
    s/(-m|--message)([ =]+)"((?:\\.|[^"\\])*)"/\1\2"STRIPPED_MSG"/g;
    s/(-m|--message)([ =]+)\x27[^\x27]*\x27/\1\2\x27STRIPPED_MSG\x27/g;
  '
}
