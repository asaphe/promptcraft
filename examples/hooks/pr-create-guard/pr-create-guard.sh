#!/usr/bin/env bash
# PreToolUse hook — PR creation verification guard.
#
# Blocks gh pr create when prerequisites are missing (zero diff, unpushed
# commits, uncommitted changes). On pass, emits a verification checklist
# as a model-facing reminder.
#
# Install: add to settings.json under hooks.PreToolUse[].hooks[]
#   with "if": "Bash(gh pr create*)" for targeted matching.
#
# Requires: jq, git

INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

if [ -z "$CMD" ]; then
  exit 0
fi

if ! echo "$CMD" | grep -qE 'gh +pr +create'; then
  exit 0
fi

ISSUES=""

# --- Hard checks (block if failed) ---

# Fetch latest main for accurate comparison
git fetch origin main --quiet 2>/dev/null

# 1. Zero diff vs main — PR would be empty
DIFF_STAT=$(git diff --stat origin/main...HEAD 2>/dev/null)
if [ -z "$DIFF_STAT" ]; then
  BRANCH=$(git branch --show-current 2>/dev/null)
  echo "PR CREATE BLOCKED — branch '$BRANCH' has zero diff vs origin/main. All changes already exist on main." >&2
  exit 1
fi

# 2. Branch not pushed to remote
BRANCH=$(git branch --show-current 2>/dev/null)
REMOTE_REF=$(git rev-parse "origin/$BRANCH" 2>/dev/null)
LOCAL_REF=$(git rev-parse HEAD 2>/dev/null)
if [ -z "$REMOTE_REF" ]; then
  ISSUES="${ISSUES}\n  - Branch '$BRANCH' has NOT been pushed to remote. Push first."
elif [ "$REMOTE_REF" != "$LOCAL_REF" ]; then
  ISSUES="${ISSUES}\n  - Local HEAD differs from origin/$BRANCH — unpushed commits exist. Push first."
fi

# 3. Uncommitted changes that would be missed
DIRTY=$(git status --porcelain 2>/dev/null | head -5)
if [ -n "$DIRTY" ]; then
  ISSUES="${ISSUES}\n  - Uncommitted changes exist that won't be in the PR:\n$(echo "$DIRTY" | sed 's/^/      /')"
fi

# Block on hard issues
if [ -n "$ISSUES" ]; then
  printf "PR CREATE BLOCKED — fix before creating:\n%b\n" "$ISSUES" >&2
  exit 1
fi

# --- Verification checklist (emit as reminder, do not block) ---

FILE_COUNT=$(echo "$DIFF_STAT" | tail -1 | grep -oE '[0-9]+ file' | grep -oE '[0-9]+')
COMMIT_COUNT=$(git rev-list --count origin/main..HEAD 2>/dev/null)
INSERTIONS=$(echo "$DIFF_STAT" | tail -1 | grep -oE '[0-9]+ insertion' | grep -oE '[0-9]+')
DELETIONS=$(echo "$DIFF_STAT" | tail -1 | grep -oE '[0-9]+ deletion' | grep -oE '[0-9]+')

cat >&2 <<CHECKLIST
PR PRE-CREATION VERIFICATION — ${FILE_COUNT:-0} files, ${COMMIT_COUNT:-0} commits, +${INSERTIONS:-0}/-${DELETIONS:-0} lines:
  [ ] Diff reviewed — changes match what was intended (no accidental inclusions)
  [ ] PR body accurately describes the FINAL state of changes
  [ ] Base branch is correct (should be main unless targeting a release branch)
  [ ] Linked ticket/issue updated
  [ ] Tests pass locally (or explicitly noted as untestable)
CHECKLIST

exit 0
