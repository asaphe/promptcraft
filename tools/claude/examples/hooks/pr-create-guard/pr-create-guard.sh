#!/usr/bin/env bash
# PreToolUse hook — PR creation verification guard.
#
# Blocks gh pr create when prerequisites are missing (zero diff, unpushed
# commits, uncommitted changes). On pass, emits a verification checklist
# as a model-facing reminder. Also covers `gh stack submit`, which creates or
# updates every PR in a stack rather than one.
#
# Install: add to settings.json under hooks.PreToolUse[].hooks[]
#   with "if": "Bash(gh *)" — matching only the create form skips the stack form.
#
# Requires: jq, git

LIB="$(dirname "$0")/../_lib"
# shellcheck source=/dev/null  # runtime-only source
[ -f "$LIB/strip-cmd.sh" ] && source "$LIB/strip-cmd.sh"
# shellcheck source=/dev/null  # runtime-only source
[ -f "$LIB/resolve-workdir.sh" ] && source "$LIB/resolve-workdir.sh"

INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

if [ -z "$CMD" ]; then
  exit 0
fi

# Match the stripped form, or the guard fires on its own trigger quoted in a -m body.
if command -v strip_cmd >/dev/null 2>&1; then
  CMD_MATCH=$(strip_cmd "$CMD")
else
  CMD_MATCH="$CMD"
fi

# The N-PR form of `pr create`. Every check below is single-branch, so this branches early.
IS_STACK=""
if echo "$CMD_MATCH" | grep -qE 'gh[[:space:]]([^|;&]* )?stack +submit([[:space:]]|$)'; then
  IS_STACK=yes
elif ! echo "$CMD_MATCH" | grep -qE 'gh[[:space:]]([^|;&]* )?pr +create([[:space:]]|$)'; then
  exit 0
fi

ISSUES=""

# A leading `cd <worktree> &&` or `-C <dir>` puts the real repo outside this hook's cwd.
GITC=()
if command -v resolve_workdir >/dev/null 2>&1; then
  WORK_DIR=$(resolve_workdir "$CMD")
  [ -n "$WORK_DIR" ] && [ -d "$WORK_DIR" ] && GITC=(-C "$WORK_DIR")
fi

# Detect default branch name. Falls back to `main` when origin/HEAD is not set.
DEFAULT_BRANCH=$(git "${GITC[@]}" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||' || true)
DEFAULT_BRANCH="${DEFAULT_BRANCH:-main}"

if [ -n "$IS_STACK" ]; then
  DIRTY=$(git "${GITC[@]}" status --porcelain 2>/dev/null | head -5)
  if [ -n "$DIRTY" ]; then
    printf "STACK SUBMIT BLOCKED — uncommitted changes would be missing from the stack:\n%s\n" "$DIRTY" >&2
    exit 2
  fi
  read -r -d '' STACK_CHECKLIST <<'STACKCHECK' || true
STACK SUBMIT — this creates or updates EVERY pull request in the stack, not one. Verify before proceeding:
  [ ] Every layer branch satisfies your branch-protection naming rules — auto-generated layer names are commonly rejected on push
  [ ] Layer order and each layer's base are what you intend
  [ ] Each layer is independently reviewable: one coherent change, not an arbitrary commit split
  [ ] Each layer's PR body stands on its own — a reviewer sees one layer, not the stack
  [ ] Every layer costs its own round of required approvals — confirm N is intended, not 1
  [ ] The bottom layer targets the default branch; cross-repo stacks are unsupported
REMINDER: merging remains the maintainer's action for stacks too, and the stack merge form lands every layer beneath the target in one operation.
STACKCHECK
  jq -n --arg ctx "$STACK_CHECKLIST" \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", additionalContext: $ctx}}'
  exit 0
fi

git "${GITC[@]}" fetch origin "$DEFAULT_BRANCH" --quiet 2>/dev/null

# Unresolvable means the check could not run; blocking would assert a zero diff nobody measured.
if ! git "${GITC[@]}" rev-parse --verify --quiet "origin/${DEFAULT_BRANCH}" >/dev/null 2>&1; then
  exit 0
fi
DIFF_STAT=$(git "${GITC[@]}" diff --stat "origin/${DEFAULT_BRANCH}...HEAD" 2>/dev/null)
if [ -z "$DIFF_STAT" ]; then
  BRANCH=$(git "${GITC[@]}" branch --show-current 2>/dev/null)
  echo "PR CREATE BLOCKED — branch '$BRANCH' has zero diff vs origin/${DEFAULT_BRANCH}. All changes already exist on the default branch." >&2
  exit 2
fi

BRANCH=$(git "${GITC[@]}" branch --show-current 2>/dev/null)
REMOTE_REF=$(git "${GITC[@]}" rev-parse "origin/$BRANCH" 2>/dev/null)
LOCAL_REF=$(git "${GITC[@]}" rev-parse HEAD 2>/dev/null)
if [ -z "$REMOTE_REF" ]; then
  ISSUES="${ISSUES}\n  - Branch '$BRANCH' has NOT been pushed to remote. Push first."
elif [ "$REMOTE_REF" != "$LOCAL_REF" ]; then
  ISSUES="${ISSUES}\n  - Local HEAD differs from origin/$BRANCH — unpushed commits exist. Push first."
fi

# 3. Uncommitted changes that would be missed
DIRTY=$(git "${GITC[@]}" status --porcelain 2>/dev/null | head -5)
if [ -n "$DIRTY" ]; then
  ISSUES="${ISSUES}\n  - Uncommitted changes exist that won't be in the PR:\n$(echo "$DIRTY" | sed 's/^/      /')"
fi

# Block on hard issues
if [ -n "$ISSUES" ]; then
  printf "PR CREATE BLOCKED — fix before creating:\n%b\n" "$ISSUES" >&2
  exit 2
fi

# --- Verification checklist (emit as reminder, do not block) ---

FILE_COUNT=$(echo "$DIFF_STAT" | tail -1 | grep -oE '[0-9]+ file' | grep -oE '[0-9]+')
COMMIT_COUNT=$(git "${GITC[@]}" rev-list --count "origin/${DEFAULT_BRANCH}..HEAD" 2>/dev/null)
INSERTIONS=$(echo "$DIFF_STAT" | tail -1 | grep -oE '[0-9]+ insertion' | grep -oE '[0-9]+')
DELETIONS=$(echo "$DIFF_STAT" | tail -1 | grep -oE '[0-9]+ deletion' | grep -oE '[0-9]+')

# additionalContext on stdout, not stderr: the harness discards stderr on exit 0, so a checklist written there reaches no one.
read -r -d '' CHECKLIST <<CHECKLIST || true
PR PRE-CREATION VERIFICATION — ${FILE_COUNT:-0} files, ${COMMIT_COUNT:-0} commits, +${INSERTIONS:-0}/-${DELETIONS:-0} lines:
  [ ] Diff reviewed — changes match what was intended (no accidental inclusions)
  [ ] PR body accurately describes the FINAL state of changes
  [ ] Base branch is correct (should be main unless targeting a release branch)
  [ ] Linked ticket/issue updated
  [ ] Tests pass locally (or explicitly noted as untestable)
CHECKLIST

jq -n --arg ctx "$CHECKLIST" \
  '{hookSpecificOutput: {hookEventName: "PreToolUse", additionalContext: $ctx}}'

exit 0
