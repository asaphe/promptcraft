#!/usr/bin/env bash
# resolve_workdir <command> — the repo a git command acts on, or nothing.
# see: tools/claude/examples/hooks/_lib/README.md § resolve-workdir.sh — why `cd <dir> && git <verb>` must resolve too

resolve_workdir() {
  local cmd="$1" dir
  dir=$(printf '%s\n' "$cmd" | grep -oE -- '-C [^ ]+' | head -1 | awk '{print $2}')
  # -C wins: when a command carries both, it is what git acts on.
  if [ -z "$dir" ]; then
    dir=$(printf '%s\n' "$cmd" | sed -nE "s/^[[:space:]]*cd[[:space:]]+(\"([^\"]+)\"|'([^']+)'|([^[:space:]&;|]+)).*/\2\3\4/p")
  fi
  # A quoted ~ never expands, so [ -d "~/repo" ] is false and the caller falls back to its own cwd.
  # shellcheck disable=SC2088  # case patterns matching a literal ~, not paths to expand
  case "$dir" in
    "~") dir="$HOME" ;;
    "~/"*) dir="$HOME/${dir#\~/}" ;;
  esac
  printf '%s' "$dir"
}
