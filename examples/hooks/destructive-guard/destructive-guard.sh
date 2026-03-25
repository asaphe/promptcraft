#!/usr/bin/env bash
# PreToolUse hook — hard-blocks destructive git/GitHub operations.
#
# Install: add to settings.json under hooks.PreToolUse[].hooks[]
#   { "type": "command", "command": "/path/to/destructive-guard.sh" }
#
# Uses exit code 2 for hard blocks that override allow-list permissions.
# When blocked, Claude must ask the user before proceeding.
#
# Requires: jq

set -euo pipefail

INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

if [ -z "$CMD" ]; then
  exit 0
fi

REASON=""

# --- GitHub CLI: visible shared-state actions ---

if echo "$CMD" | grep -qE 'gh\s+pr\s+close'; then
  REASON="gh pr close — closes a PR, losing review threads and CI history. Fix the branch in-place with force-push instead."
fi

if echo "$CMD" | grep -qE 'gh\s+pr\s+merge'; then
  REASON="gh pr merge — merges a PR. Confirm with the user first."
fi

if echo "$CMD" | grep -qE 'gh\s+pr\s+create'; then
  REASON="gh pr create — creating a PR is a visible shared action. Confirm with the user first."
fi

if echo "$CMD" | grep -qE 'gh\s+run\s+delete'; then
  REASON="gh run delete — permanently removes CI run history."
fi

# --- Git: history rewriting and data loss ---

if echo "$CMD" | grep -qE 'git\s+push\s+\S+\s+:'; then
  REASON="git push origin :branch — deletes a remote branch, which auto-closes any PR using it."
fi

if echo "$CMD" | grep -qE 'git\s+push\s+.*--(force|force-with-lease)'; then
  REASON="git push --force — rewrites remote history. Confirm with the user first."
fi

if echo "$CMD" | grep -qE 'git\s+branch\s+-D'; then
  REASON="git branch -D — force-deletes a branch that may have unmerged work."
fi

if echo "$CMD" | grep -qE 'git\s+reset\s+--hard'; then
  REASON="git reset --hard — discards all uncommitted changes permanently."
fi

if echo "$CMD" | grep -qE 'git\s+checkout\s+--\s'; then
  REASON="git checkout -- — discards uncommitted file changes."
fi

if echo "$CMD" | grep -qE 'git\s+restore\s+' && ! echo "$CMD" | grep -qE 'git\s+restore\s+--staged'; then
  REASON="git restore — discards uncommitted file changes."
fi

# --- Block if matched ---

if [ -n "$REASON" ]; then
  echo "$REASON" >&2
  exit 2
fi

# No match — allow
exit 0
