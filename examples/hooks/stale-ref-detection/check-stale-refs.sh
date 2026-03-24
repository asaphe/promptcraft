#!/usr/bin/env bash
# Validate that file references in .claude/ docs point to existing files.
# Usage: .claude/hooks/check-stale-refs.sh [--deleted-only]
#   --deleted-only: only check files deleted in current branch vs origin/main
#   (no flag): check backtick-quoted paths containing / in .claude/ markdown
#
# Can be run standalone (./check-stale-refs.sh) or integrated into a pre-push hook.
# Layer: Project (.claude/hooks/) — repo-specific validation.

# shellcheck disable=SC2016
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
cd "$ROOT"

FAILURES=""

if [ "${1:-}" = "--deleted-only" ]; then
  # Check only deleted files — fast mode for pre-push hooks
  DELETED=$(git diff origin/main...HEAD --name-only --diff-filter=D -- '*.md' 2>/dev/null || true)
  [ -z "$DELETED" ] && exit 0

  for deleted_file in $DELETED; do
    base=$(basename "$deleted_file")
    while IFS= read -r ref_file; do
      FAILURES="${FAILURES}\n  $ref_file references deleted '$base'"
    done < <(grep -rlF "$base" .claude/ 2>/dev/null | grep -vF '.git' || true)
  done
else
  # Full scan: check backtick-quoted paths that contain a /
  while IFS= read -r md_file; do
    while IFS= read -r ref; do
      # Skip URLs, template placeholders, glob patterns, temp files, and examples
      echo "$ref" | grep -qE '^https?://|<|{|\*|^/tmp/|XXXX|path/to/' && continue
      echo "$ref" | grep -qF '/' || continue
      if [ ! -f "$ref" ]; then
        FAILURES="${FAILURES}\n  $md_file → $ref (not found)"
      fi
    done < <(grep -oE '`[a-zA-Z0-9_./ -]+\.(md|mdc|sh|py|ts|json|yaml|yml)`' "$md_file" 2>/dev/null | tr -d '`' | sort -u || true)
  done < <(find .claude/ -name '*.md' -not -path '*/.git/*' 2>/dev/null)
fi

if [ -n "$FAILURES" ]; then
  printf "Stale file references found:%b\n" "$FAILURES" >&2
  exit 1
fi

echo "No stale references found."
exit 0
