#!/usr/bin/env bash
# worktree-preflight.sh — Block git WRITE ops on a guarded repo root when the
# root is not on main. Convention: repo roots stay on main, branch work happens
# in worktrees under /tmp/. A non-main root signals another session is actively
# using it; writing there pollutes their work.
#
# Configure WORKTREE_GUARD_ROOT to your monorepo parent directory (default:
# $HOME/repos). Only direct children of this path are guarded — worktrees in
# /tmp/ and unrelated repos are passed through.
#
# Complements destructive-guard.sh (which already blocks cross-repo branch
# switching). This hook covers commit/push/merge/rebase/reset/etc.

INPUT=$(cat)
HOOK_DIAG_NAME="worktree-preflight"
[ -f "$(dirname "$0")/../_lib/hook-diag.sh" ] && source "$(dirname "$0")/../_lib/hook-diag.sh"
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
[ -z "$CMD" ] && exit 0

source "$(dirname "$0")/../_lib/strip-cmd.sh"
CMD_STRIPPED=$(strip_cmd "$CMD")

# Gate on git write ops only (read ops like log/status/diff are fine on any branch).
if ! echo "$CMD_STRIPPED" | grep -qE 'git[[:space:]]([^|;&]* )?(commit|push|merge|rebase|reset|cherry-pick|revert|pull|am|apply|stash[[:space:]]+(push|save)|tag|branch[[:space:]]+(-D|-d|-m|--delete|--move)|add|rm|mv)([[:space:]]|$)'; then
  exit 0
fi

# Resolve target repo from cd prefix, git -C, or current directory.
TARGET=""
if echo "$CMD_STRIPPED" | grep -qE '(^|[;&|]) *cd +[^ ;&|]+'; then
  TARGET=$(echo "$CMD" | grep -oE '(^|[;&|]) *cd +[^ ;&|]+' | tail -1 | sed -E 's/^[^c]*cd +//')
fi
if echo "$CMD_STRIPPED" | grep -qE 'git +-C +'; then
  TARGET=$(echo "$CMD" | grep -oE 'git +-C +[^ ]+' | head -1 | awk '{print $NF}')
fi

if [ -n "$TARGET" ]; then
  TARGET="${TARGET/#\~/$HOME}"
  TARGET_ABS=$(cd "$TARGET" 2>/dev/null && pwd)
else
  TARGET_ABS=$(pwd)
fi

[ -z "$TARGET_ABS" ] && exit 0

# Configure this to your monorepo parent. Only direct children are guarded.
GUARD_ROOT="${WORKTREE_GUARD_ROOT:-$HOME/repos}"

case "$TARGET_ABS" in
  "$GUARD_ROOT/"*)
    REL="${TARGET_ABS#"$GUARD_ROOT"/}"
    case "$REL" in
      */*) exit 0 ;;   # subdirectory of a guarded repo, not the root itself
      "") exit 0 ;;
    esac
    [ -d "$TARGET_ABS/.git" ] || exit 0
    ;;
  *)
    exit 0
    ;;
esac

BRANCH=$(git -C "$TARGET_ABS" branch --show-current 2>/dev/null)
if [ -z "$BRANCH" ] || [ "$BRANCH" = "main" ] || [ "$BRANCH" = "master" ]; then
  exit 0
fi

REPO_NAME=$(basename "$TARGET_ABS")
echo "BLOCKED: ${TARGET_ABS} is on branch '${BRANCH}', not main." >&2
echo "" >&2
echo "Repo roots stay on main; branch work belongs in worktrees under /tmp/." >&2
echo "A non-main root signals another session is actively using ${REPO_NAME} — writing here will pollute their work." >&2
echo "" >&2
echo "If ${REPO_NAME} is yours to use:" >&2
echo "  git -C ${TARGET_ABS} status                    # confirm clean / no other session active" >&2
echo "  git -C ${TARGET_ABS} checkout main             # restore root state" >&2
echo "  git worktree add /tmp/<name> -b ${BRANCH} main # do branch work in a worktree" >&2
exit 2
