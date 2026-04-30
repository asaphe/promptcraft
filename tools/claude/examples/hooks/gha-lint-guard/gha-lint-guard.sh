#!/usr/bin/env bash
# gha-lint-guard.sh — runs actionlint on staged .github/workflows/*.yaml files
# at git commit time. BLOCKS the commit on failure (exit 2).
# Handles worktrees via git -C <path> commit.

INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

if [ -z "$CMD" ]; then
  exit 0
fi

# Flag-permissive: catches `git commit`, `git -C dir commit`, `git --no-pager commit`.
if ! echo "$CMD" | grep -qE 'git[[:space:]]([^|;&]* )?commit([[:space:]]|$)'; then
  exit 0
fi

# Handle worktree: extract -C path and cd into it so git diff --cached resolves correctly.
WORK_DIR=$(echo "$CMD" | grep -oE -- '-C [^ ]+' | head -1 | awk '{print $2}')
if [ -n "$WORK_DIR" ] && [ -d "$WORK_DIR" ]; then
  cd "$WORK_DIR" || exit 0
fi

# Skip if no workflow files staged.
STAGED=$(git diff --cached --name-only 2>/dev/null | grep -E '\.github/workflows/.*\.ya?ml$' || true)
if [ -z "$STAGED" ]; then
  exit 0
fi

# Skip if actionlint is not installed — log and pass.
if ! command -v actionlint >/dev/null 2>&1; then
  echo "[gha-lint-guard] actionlint not installed — skipping (install: brew install actionlint)" >&2
  exit 0
fi

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
AL_ARGS=()
[ -f "$REPO_ROOT/.github/actionlint.yaml" ] && AL_ARGS+=(-config-file "$REPO_ROOT/.github/actionlint.yaml")

AL_OUT=$(actionlint "${AL_ARGS[@]}" 2>&1)
AL_EXIT=$?

if [ $AL_EXIT -ne 0 ]; then
  printf "\n[gha-lint-guard] actionlint FAILED on staged workflow files — commit blocked.\n\n%s\n" "$AL_OUT" >&2
  printf "\nFix the errors above, then re-run the commit.\n" >&2
  exit 2
fi

exit 0
