#!/usr/bin/env bash
# Commit attribution guard — hard-block AI attribution and `claude/` branch prefix.
#
# Why this hook (not just CLAUDE.md rule + CLAUDE_CODE_UNDERCOVER=1):
#   - CLAUDE_CODE_UNDERCOVER=1 suppresses Claude Code's automatic Co-Authored-By
#     trailer, but the model can still TYPE attribution into a heredoc commit
#     message.
#   - `claude/` branch prefix is Claude Code's autonomous-branch default; rule
#     forbids it but the model regresses in new sessions.
# This hook catches both at git commit / git branch time, before the action.

INPUT=$(cat)
HOOK_DIAG_NAME="commit-attribution-guard"
[ -f "$(dirname "$0")/../_lib/hook-diag.sh" ] && source "$(dirname "$0")/../_lib/hook-diag.sh"
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

[ -z "$CMD" ] && exit 0

REASON=""

# Flag-permissive pattern catches `git -C dir commit`, `git --no-pager commit`, etc.
if echo "$CMD" | grep -qE 'git[[:space:]]([^|;&]* )?commit([[:space:]]|$)'; then
  if echo "$CMD" | grep -qiE 'co-authored-by:[[:space:]]*(claude|anthropic)'; then
    REASON="commit message contains 'Co-Authored-By: Claude/Anthropic' — forbidden by NO AI attribution rule"
  elif echo "$CMD" | grep -qE 'Generated with \[?Claude Code\]?'; then
    REASON="commit message contains 'Generated with Claude Code' marker — forbidden by NO AI attribution rule"
  elif echo "$CMD" | grep -qiE '(claude\.ai/code|🤖[[:space:]]+generated)'; then
    REASON="commit message contains AI attribution marker — forbidden by NO AI attribution rule"
  fi
fi

if [ -z "$REASON" ]; then
  source "$(dirname "$0")/../_lib/strip-cmd.sh"
  CMD_STRIPPED=$(strip_cmd "$CMD")
  if echo "$CMD_STRIPPED" | grep -qE 'git[[:space:]]([^|;&]* )?(checkout|switch|branch|push).*[[:space:]]claude/'; then
    REASON="branch name uses 'claude/' prefix — forbidden by branch naming rule. Use 'dev-XXX-short-description' or similar."
  fi
fi

if [ -n "$REASON" ]; then
  echo "BLOCKED: $REASON" >&2
  echo "" >&2
  echo "Fix:" >&2
  echo "  - Rewrite the commit message without attribution lines, OR" >&2
  echo "  - Rename the branch (git branch -m claude/foo dev-XXXX-foo)" >&2
  exit 2
fi

exit 0
