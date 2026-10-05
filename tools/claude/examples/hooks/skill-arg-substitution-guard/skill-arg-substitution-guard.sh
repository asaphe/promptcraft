#!/usr/bin/env bash
# Block a SKILL.md or command .md edit that writes a $<digits> token the skill loader will replace with an argument.
# Registration JSON: README.md. Requires: jq, perl.
set -euo pipefail

INPUT=$(cat)
# shellcheck disable=SC2034  # read by the sourced hook-diag.sh
HOOK_DIAG_NAME="skill-arg-substitution-guard"
[ -f "$(dirname "$0")/../_lib/hook-diag.sh" ] && source "$(dirname "$0")/../_lib/hook-diag.sh"

FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)
case "$FILE_PATH" in
  */SKILL.md | */commands/*.md) ;;
  *) exit 0 ;;
esac

# the new text only: Write's content, Edit's new_string, every MultiEdit new_string
if ! NEW_TEXT=$(printf '%s' "$INPUT" | jq -er '
    .tool_input
    | if has("content") then .content
      elif has("new_string") then .new_string
      elif (.edits | type) == "array" then [.edits[] | .new_string // ""] | join("\n")
      else error("no new text") end' 2>/dev/null); then
  echo "BLOCKED: could not read the new text of ${FILE_PATH}, so this guard cannot check it for \$<digits> tokens the skill loader substitutes." >&2
  echo "Re-issue the edit as Write (content), Edit (new_string) or MultiEdit (edits[].new_string)." >&2
  exit 2
fi

# the loader's rule, read from the Claude Code binary: \$\d+(?!\w); a single backslash escapes it, a doubled one does not
HITS=$(printf '%s\n' "$NEW_TEXT" | perl -ne 'print "  $.: $_" if /(?<!(?<!\\)\\)\$\d+(?!\w)/' | cut -c1-160 | head -5)
[ -z "$HITS" ] && exit 0

echo "BLOCKED: ${FILE_PATH} would contain \$<digits> followed by a non-word character:" >&2
printf '%s\n' "$HITS" >&2
echo "When this skill or command runs with arguments, Claude Code replaces that token with the matching argument, so an awk field or a price in prose is silently rewritten." >&2
echo "Escape it as \\\$N (the documented escape), or write awk fields as \$(N) (the same field), shell positionals as \${N}, and prose without the \$ (\"USD 5\"). \$ARGUMENTS and \$ARGUMENTS[N] are intended substitutions and are allowed." >&2
exit 2
