#!/usr/bin/env bash
# PostToolUse hook: run linter/formatter on edited files.
# Receives hook input as JSON on stdin with tool_input.file_path.
#
# Register in .claude/settings.json:
#   "PostToolUse": [{
#     "matcher": "Edit|Write",
#     "hooks": [{"type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/post-edit-lint.sh", "timeout": 15}]
#   }]
#
# Layer: Project (.claude/settings.json) — team-wide, everyone benefits from consistent formatting.
# Dependencies: jq (required), all linters optional (degrade gracefully).

set -euo pipefail

command -v jq &>/dev/null || exit 0

INPUT=$(cat)
FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty')
[ -z "$FILE_PATH" ] && exit 0
[ ! -f "$FILE_PATH" ] && exit 0

ROOT="$(git -C "$(dirname "$FILE_PATH")" rev-parse --show-toplevel 2>/dev/null || echo "")"
[ -z "$ROOT" ] && exit 0

REL_PATH="${FILE_PATH#"$ROOT"/}"
EXT="${FILE_PATH##*.}"
BASENAME="$(basename "$FILE_PATH")"

# Extension-based checks run first (shell scripts, Dockerfiles can appear anywhere)
case "$EXT" in
  sh)
    if command -v shellcheck &>/dev/null; then
      shellcheck "$FILE_PATH" 2>&1 | head -10 || true
    fi
    ;;
esac

case "$BASENAME" in
  Dockerfile*)
    if command -v hadolint &>/dev/null; then
      hadolint "$FILE_PATH" 2>&1 | head -10 || true
    fi
    ;;
esac

# Path-based checks for language-specific tools
# Customize these paths and tools to match your project structure.
case "$REL_PATH" in
  infra/terraform/*)
    case "$EXT" in
      tf|tfvars)
        terraform fmt "$FILE_PATH" 2>/dev/null || true
        ;;
    esac
    ;;
  python/*)
    case "$EXT" in
      py)
        cd "$ROOT/python" || exit 0
        # Replace with your Python linter (ruff, black, flake8, etc.)
        poetry run ruff check --fix --quiet "$FILE_PATH" 2>/dev/null || true
        poetry run ruff format --quiet "$FILE_PATH" 2>/dev/null || true
        ;;
    esac
    ;;
  typescript/*|frontend/*)
    case "$EXT" in
      ts|tsx|js|jsx)
        cd "$ROOT/typescript" || exit 0
        # Replace with your JS/TS formatter (prettier, eslint, biome, etc.)
        pnpm prettier --write "$FILE_PATH" 2>/dev/null || true
        ;;
    esac
    ;;
  .github/workflows/*)
    case "$EXT" in
      yml|yaml)
        if command -v actionlint &>/dev/null; then
          actionlint "$FILE_PATH" 2>&1 | head -5 || true
        fi
        ;;
    esac
    ;;
esac
