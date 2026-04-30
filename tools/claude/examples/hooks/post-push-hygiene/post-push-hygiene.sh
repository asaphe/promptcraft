#!/usr/bin/env bash
# PostToolUse:Bash — fires after git push succeeds.
# Reminds to resolve threads, update the PR body, and update the issue tracker.

INPUT=$(cat)
CMD=$(printf '%s\n' "$INPUT" | jq -r '.tool_input.command // empty')
# Claude Code's PostToolUse payload field is .tool_response.stdout in current
# releases; older versions used .tool_result.stdout. Try both for portability.
RESULT=$(printf '%s\n' "$INPUT" | jq -r '.tool_response.stdout // .tool_result.stdout // empty')

# Flag-permissive: catches `git push`, `git -C dir push`, `git --no-pager push`.
if ! printf '%s\n' "$CMD" | grep -qE 'git[[:space:]]([^|;&]* )?push([[:space:]]|$)'; then
  exit 0
fi

# Skip on push failure — checklist would be misleading.
if printf '%s\n' "$RESULT" | grep -qE '(rejected|error|fatal|failed)'; then
  exit 0
fi

# Invalidate repo-scoped PR cache (if any) so the next prompt re-fetches fresh PR state.
BRANCH=$(git --no-optional-locks branch --show-current 2>/dev/null)
REPO_NAME=$(git remote get-url origin 2>/dev/null | sed 's|.*/||' | sed 's|\.git$||')
if [ -n "$BRANCH" ] && [ "$BRANCH" != "main" ] && [ "$BRANCH" != "master" ] && [ -n "$REPO_NAME" ]; then
  SAFE_BRANCH=$(printf '%s' "$BRANCH" | tr '/' '_' | tr ' ' '-')
  rm -f "/tmp/claude-pr-cache-${REPO_NAME}-${SAFE_BRANCH}"
fi

TF_LINE=""
TF_FILES=$(git diff --name-only origin/main...HEAD 2>/dev/null | grep -E '\.tf$' | head -5)
[ -n "$TF_FILES" ] && TF_LINE="\n- [ ] TERRAFORM: .tf changes pushed — apply before/after merge? Document in PR body."

CHECKLIST="Post-push checklist:\n- [ ] Resolve all addressed review threads (GraphQL resolveReviewThread)\n- [ ] Update PR body to reflect final state (scope expanded since last push? update now)\n- [ ] Update issue tracker / ticket status${TF_LINE}"

jq -n --arg ctx "$CHECKLIST" '{
  "hookSpecificOutput": {
    "hookEventName": "PostToolUse",
    "additionalContext": $ctx
  }
}'
