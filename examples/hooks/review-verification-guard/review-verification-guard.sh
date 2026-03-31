#!/usr/bin/env bash
# Review verification guard — blocks PR review/comment posting commands
# with operation-specific verification checklists.
#
# Catches: gh api ...reviews, gh pr comment, gh api ...comments
# Does NOT block: reading reviews/comments, CI status checks, general gh commands
#
# Register in settings.json:
# "PreToolUse": [{ "matcher": "Bash", "hooks": [{ "type": "command", "command": "/path/to/review-verification-guard.sh" }] }]

INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

if [ -z "$CMD" ]; then
  exit 0
fi

REASON=""

# PR review posting (via API — POST is the default method)
if echo "$CMD" | grep -qE 'gh +api +repos/.+/pulls/[0-9]+/reviews' && ! echo "$CMD" | grep -qE '\-X +(GET|DELETE)'; then
  REASON="Posting PR review — VERIFICATION CHECKLIST:
  [ ] Read every file from the PR branch HEAD (git show branch:file), not the patch diff
  [ ] Checked ALL existing PR comments (bot + human) for duplicate findings
  [ ] Verified each finding against live state (API, CLI, actual config)
  [ ] Confirmed function signatures/imports match the final commit, not intermediate ones
  [ ] Findings classified correctly: CRITICAL blocks merge, ISSUE should fix, SUGGESTION is optional"
fi

# PR body comment
if echo "$CMD" | grep -qE 'gh +pr +comment '; then
  REASON="Posting PR comment — VERIFICATION CHECKLIST:
  [ ] All claims verified against live state (config references != provisioned resources)
  [ ] No speculative claims — everything backed by evidence"
fi

# Inline comment via API
if echo "$CMD" | grep -qE 'gh +api +repos/.+/pulls/[0-9]+/comments ' && ! echo "$CMD" | grep -qE '\-X +(GET|DELETE)'; then
  REASON="Posting PR inline comment — VERIFICATION CHECKLIST:
  [ ] Finding verified against actual code on branch HEAD (not diff)
  [ ] Not a duplicate of an existing comment on this PR
  [ ] Verified against live state if making infrastructure claims"
fi

# Comment update (lighter check)
if echo "$CMD" | grep -qE 'gh +api +repos/.+/pulls/comments/[0-9]+ +-X +PATCH'; then
  REASON="Updating PR comment — does the updated content reflect verified findings only?"
fi

if [ -n "$REASON" ]; then
  jq -n \
    --arg reason "$REASON" \
    '{
      "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "block",
        "permissionDecisionReason": $reason
      }
    }'
  exit 0
fi

# No match — allow
exit 0
