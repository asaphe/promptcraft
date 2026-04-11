#!/usr/bin/env bash
# PreToolUse hook — two-tier destructive operation guard.
#
# HARD BLOCK (exit 2): Irreversible data loss. Cannot be overridden by
#   Bash(*) permissions. User must run the command themselves.
#
# SOFT BLOCK (JSON + exit 0): Risky actions that need confirmation.
#   User can approve in the permission prompt when Bash(*) is set.
#
# Install: add to settings.json under hooks.PreToolUse[].hooks[]
#   { "type": "command", "command": "/path/to/destructive-guard.sh" }
#
# Requires: jq

set -euo pipefail

INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

if [ -z "$CMD" ]; then
  exit 0
fi

HARD_REASON=""
SOFT_REASON=""

# =====================================================================
# HARD BLOCKS — irreversible data loss, exit 2
# Cannot be overridden by Bash(*) or any allow-list permission.
# =====================================================================

# git push to main/master (bypass PR process)
# Worktree-aware: if the command does "cd /tmp/worktree && ... && git push",
# check the branch in that directory, not the hook's CWD.
# Force-push to main/master is even worse than regular push — hard block it separately.
# Reuse awk parsing to skip flags and extract the positional ref argument.
if echo "$CMD" | grep -qE 'git +push +.*--(force|force-with-lease)'; then
  FORCE_PORTION=$(echo "$CMD" | grep -oE 'git +push[^;&|]*' | head -1)
  FORCE_REF=$(echo "$FORCE_PORTION" | sed 's/git *push *//' | awk 'BEGIN{n=0} {for(i=1;i<=NF;i++) if(substr($i,1,1)!="-") {n++; if(n==2) {print $i; exit}}}')
  if [ "$FORCE_REF" = "main" ] || [ "$FORCE_REF" = "master" ]; then
    HARD_REASON="git push --force to main — rewrites shared history on the default branch."
  elif echo "$FORCE_REF" | grep -qE '(^|:)(main|master)$'; then
    HARD_REASON="git push --force to main — rewrites shared history on the default branch."
  fi
fi

# Refspec-aware: "git push origin feature:remote" and "git push origin branch"
# (where branch is not main) are safe — they push a specific ref, not current branch.
if [ -z "$HARD_REASON" ] && echo "$CMD" | grep -qE 'git +push([[:space:]]|$)' && ! echo "$CMD" | grep -qE 'git +push +.*--(force|force-with-lease)'; then
  PUSH_DIR=""
  if echo "$CMD" | grep -qE 'cd +[^ ;&]+ *[;&].*git +push'; then
    PUSH_DIR=$(echo "$CMD" | grep -oE 'cd +[^ ;&]+' | tail -1 | sed 's/^cd *//')
  fi

  # Extract the git push portion and parse positional args (remote, refspec).
  # Use awk to keep only words that don't start with "-" (flags like -u, --set-upstream).
  # Plain sed 's/--*[^ ]*//g' would corrupt hyphenated branch names (main-hotfix → main).
  PUSH_PORTION=$(echo "$CMD" | grep -oE 'git +push[^;&|]*' | head -1)
  PUSH_REMOTE=$(echo "$PUSH_PORTION" | sed 's/git *push *//' | awk '{for(i=1;i<=NF;i++) if(substr($i,1,1)!="-") {print $i; exit}}')
  PUSH_REF=$(echo "$PUSH_PORTION" | sed 's/git *push *//' | awk 'BEGIN{n=0} {for(i=1;i<=NF;i++) if(substr($i,1,1)!="-") {n++; if(n==2) {print $i; exit}}}')

  WILL_PUSH_MAIN=""
  if [ -z "$PUSH_REF" ]; then
    # No explicit ref — pushes current branch. Check which branch we're on.
    if [ -n "$PUSH_DIR" ]; then
      BRANCH=$(git -C "$PUSH_DIR" branch --show-current 2>/dev/null || true)
    else
      BRANCH=$(git branch --show-current 2>/dev/null || true)
    fi
    if [ "$BRANCH" = "main" ] || [ "$BRANCH" = "master" ]; then
      WILL_PUSH_MAIN=1
    fi
  elif [ "$PUSH_REF" = "main" ] || [ "$PUSH_REF" = "master" ]; then
    WILL_PUSH_MAIN=1
  elif echo "$PUSH_REF" | grep -qE '(^|:)(main|master)$'; then
    # Refspec pushing TO main (e.g., feature:main)
    WILL_PUSH_MAIN=1
  fi

  if [ -n "$WILL_PUSH_MAIN" ]; then
    HARD_REASON="git push on main — changes must go through a PR."
  fi
fi

# git reset --hard (permanent loss of uncommitted work)
if echo "$CMD" | grep -qE 'git +reset +--hard'; then
  HARD_REASON="git reset --hard — discards all uncommitted changes permanently."
fi

# AWS resource deletion
if echo "$CMD" | grep -qE 'aws +(rds +delete|ec2 +terminate|s3 +r[mb]|secretsmanager +delete|iam +delete|lambda +delete|sqs +(purge|delete)|sns +delete|ecr +batch-delete)'; then
  HARD_REASON="AWS delete/destroy — permanently removes cloud resources."
fi

# =====================================================================
# SOFT BLOCKS — risky but approvable, JSON + exit 0
# User sees the warning and can approve in the permission prompt.
# =====================================================================

# GitHub CLI — visible shared actions
if echo "$CMD" | grep -qE 'gh +pr +create'; then
  SOFT_REASON="gh pr create — visible shared action. Confirm with user."
fi

if echo "$CMD" | grep -qE 'gh +pr +close'; then
  SOFT_REASON="gh pr close — verify before closing: read the PR fully, check for open review threads, confirm the reason, verify no unmerged work will be lost."
fi

if echo "$CMD" | grep -qE 'gh +pr +merge'; then
  SOFT_REASON="gh pr merge — visible shared action. Confirm with user."
fi

if echo "$CMD" | grep -qE 'gh +run +delete'; then
  SOFT_REASON="gh run delete — permanently removes CI run history."
fi

# Git — history rewriting (reversible via reflog)
if echo "$CMD" | grep -qE 'git +push +[^[:space:]]+ +:'; then
  SOFT_REASON="git push :branch — deletes a remote branch."
fi

if echo "$CMD" | grep -qE 'git +push +.*--(force|force-with-lease)'; then
  SOFT_REASON="git push --force — rewrites remote history."
fi

if echo "$CMD" | grep -qE 'git +branch +-D'; then
  SOFT_REASON="git branch -D — force-deletes a branch."
fi

if echo "$CMD" | grep -qE 'git +(checkout +--[[:space:]]|restore +)' && ! echo "$CMD" | grep -qE 'git +restore +--staged'; then
  SOFT_REASON="git checkout/restore — discards uncommitted file changes."
fi

# Terraform
if echo "$CMD" | grep -qE 'terraform +(destroy|state +rm|force-unlock|workspace +delete)'; then
  SOFT_REASON="terraform destructive operation — confirm target and intent."
fi

# Kubectl
if echo "$CMD" | grep -qE 'kubectl +(delete|drain|cordon|scale|rollout +undo|patch) '; then
  SOFT_REASON="kubectl mutation — affects live cluster resources."
fi

# Helm
if echo "$CMD" | grep -qE 'helm +(uninstall|rollback)'; then
  SOFT_REASON="helm destructive operation — affects running releases."
fi

# =====================================================================
# Apply blocks — hard wins over soft
# =====================================================================

if [ -n "$HARD_REASON" ]; then
  echo "$HARD_REASON" >&2
  exit 2
fi

if [ -n "$SOFT_REASON" ]; then
  jq -n \
    --arg reason "$SOFT_REASON" \
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
