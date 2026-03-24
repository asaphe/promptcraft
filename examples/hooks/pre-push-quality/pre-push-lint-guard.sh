#!/usr/bin/env bash
# Pre-push lint enforcement — runs relevant linters on changed files and
# BLOCKS the push if any fail.
#
# Register in ~/.claude/settings.json (global — personal quality gate):
#   "PreToolUse": [{
#     "matcher": "Bash",
#     "hooks": [{"type": "command", "command": "~/.claude/hooks/pre-push-lint-guard.sh", "timeout": 30}]
#   }]
#
# Layer: Global (~/.claude/settings.json) — personal quality bar.
# Dependencies: jq (required), linters optional (only checked if matching files exist).

INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

if [ -z "$CMD" ]; then
  exit 0
fi

# Only match git push (skip force push — handled by destructive-guard)
if ! echo "$CMD" | grep -qE 'git\s+push(\s|$)'; then
  exit 0
fi
if echo "$CMD" | grep -qE 'git\s+push\s+.*--(force|force-with-lease)'; then
  exit 0
fi

# Get changed files relative to main
CHANGED_FILES=$(git diff --name-only origin/main...HEAD 2>/dev/null)
if [ -z "$CHANGED_FILES" ]; then
  exit 0
fi

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
FAILURES=""

# Scope check — detect PRs mixing app code with infra code
HAS_APP=$(echo "$CHANGED_FILES" | grep -qE '^(python|typescript|java|go|src)/' && echo "yes" || echo "no")
HAS_INFRA=$(echo "$CHANGED_FILES" | grep -qE '^(infra|devops|\.github|terraform)/' && echo "yes" || echo "no")
if [ "$HAS_APP" = "yes" ] && [ "$HAS_INFRA" = "yes" ]; then
  APP_DIRS=$(echo "$CHANGED_FILES" | grep -E '^(python|typescript|java|go|src)/' | cut -d/ -f1 | sort -u | tr '\n' ', ' | sed 's/,$//')
  INFRA_DIRS=$(echo "$CHANGED_FILES" | grep -E '^(infra|devops|\.github|terraform)/' | cut -d/ -f1 | sort -u | tr '\n' ', ' | sed 's/,$//')
  FAILURES="${FAILURES}\n\n### Scope warning — PR mixes app code (${APP_DIRS}) with infra (${INFRA_DIRS}).\nThis usually indicates a dirty worktree or bad rebase."
fi

# Python — ruff check + format
PY_FILES=$(echo "$CHANGED_FILES" | grep -E '\.py$' || true)
if [ -n "$PY_FILES" ]; then
  if ! RUFF_CHECK=$(cd "$REPO_ROOT" && echo "$PY_FILES" | xargs poetry run ruff check 2>&1); then
    if echo "$RUFF_CHECK" | grep -qE 'Found [0-9]+ error'; then
      FAILURES="${FAILURES}\n\n### ruff check failures:\n${RUFF_CHECK}"
    fi
  fi
  if ! RUFF_FMT=$(cd "$REPO_ROOT" && echo "$PY_FILES" | xargs poetry run ruff format --check 2>&1); then
    FAILURES="${FAILURES}\n\n### ruff format failures:\n${RUFF_FMT}"
  fi
fi

# Terraform — fmt check
TF_FILES=$(echo "$CHANGED_FILES" | grep -E '\.tf$' || true)
if [ -n "$TF_FILES" ]; then
  TF_DIRS=$(echo "$TF_FILES" | xargs -I{} dirname {} | sort -u)
  for dir in $TF_DIRS; do
    if ! FMT_OUT=$(cd "$REPO_ROOT/$dir" && terraform fmt -check -diff 2>&1); then
      FAILURES="${FAILURES}\n\n### terraform fmt failures in $dir:\n${FMT_OUT}"
    fi
  done
fi

# Shell — shellcheck
SH_FILES=$(echo "$CHANGED_FILES" | grep -E '\.(sh|bash)$' || true)
if [ -n "$SH_FILES" ]; then
  for f in $SH_FILES; do
    if [ -f "$REPO_ROOT/$f" ]; then
      if ! SC_OUT=$(shellcheck "$REPO_ROOT/$f" 2>&1); then
        FAILURES="${FAILURES}\n\n### shellcheck failures in $f:\n${SC_OUT}"
      fi
    fi
  done
fi

# Dockerfile — hadolint
DOCKER_FILES=$(echo "$CHANGED_FILES" | grep -E 'Dockerfile' || true)
if [ -n "$DOCKER_FILES" ]; then
  for f in $DOCKER_FILES; do
    if [ -f "$REPO_ROOT/$f" ]; then
      if ! HL_OUT=$(hadolint "$REPO_ROOT/$f" 2>&1); then
        FAILURES="${FAILURES}\n\n### hadolint failures in $f:\n${HL_OUT}"
      fi
    fi
  done
fi

# GitHub Actions — actionlint
GHA_FILES=$(echo "$CHANGED_FILES" | grep -E '\.github/workflows/.*\.ya?ml$' || true)
if [ -n "$GHA_FILES" ]; then
  if ! AL_OUT=$(actionlint 2>&1); then
    FAILURES="${FAILURES}\n\n### actionlint failures:\n${AL_OUT}"
  fi
fi

# Stale reference check — deleted .md files still referenced in .claude/ docs
DELETED_MD=$(echo "$CHANGED_FILES" | grep -E '\.md$' || true)
if [ -n "$DELETED_MD" ]; then
  for f in $DELETED_MD; do
    if [ ! -f "$REPO_ROOT/$f" ]; then
      base=$(basename "$f")
      refs=$(grep -rlF "$base" "$REPO_ROOT/.claude/" 2>/dev/null | grep -vF '.git' || true)
      if [ -n "$refs" ]; then
        ref_list=$(echo "$refs" | sed "s|$REPO_ROOT/||g" | tr '\n' ', ' | sed 's/,$//')
        FAILURES="${FAILURES}\n\n### Stale reference: deleted '$base' is still referenced in: ${ref_list}"
      fi
    fi
  done
fi

if [ -n "$FAILURES" ]; then
  REASON=$(printf "git push BLOCKED — quality gate failures. Fix before pushing:%b" "$FAILURES")
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

# All checks passed — allow push
exit 0
