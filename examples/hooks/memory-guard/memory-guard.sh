#!/usr/bin/env bash
# Memory guard — blocks writes to project memory for repos with multiple clones/worktrees.
# Project memory only loads for the specific filesystem path, so writing memory in
# clone-3 means it never loads in clone-1 or clone-7.
#
# Register in settings.json:
# "PreToolUse": [{ "matcher": "Write", "hooks": [{ "type": "command", "command": "/path/to/memory-guard.sh" }] }]
set -euo pipefail

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

if [ -z "$FILE_PATH" ]; then
  exit 0
fi

# Only guard project memory paths (not MEMORY.md index, which is the entry point)
if [[ "$FILE_PATH" != *"/.claude/projects/"*"/memory/"* ]] || [[ "$FILE_PATH" == *"/MEMORY.md" ]]; then
  exit 0
fi

# Check if the path contains a known multi-clone marker.
# Customize this pattern to match your clone directory naming.
# Examples: project-2, project-3, my-repo-feature-branch, etc.
#
# Option A: Match a specific naming pattern (e.g., "myproject-N" clones)
# if [[ "$FILE_PATH" != *"-myproject-"* ]]; then
#   exit 0
# fi
#
# Option B: Match any path under a parent directory known to have clones
# CLONE_PARENT="$HOME/projects"
# if [[ "$FILE_PATH" != *"$CLONE_PARENT"* ]]; then
#   exit 0
# fi
#
# Option C: Always block project memory (force use of global memory or .claude/rules/)
# This is the safest option if you use worktrees or multiple clones regularly.

echo "BLOCKED: This repo has multiple clones — project memory only loads for one filesystem path." >&2
echo "Use global ~/.claude/CLAUDE.md for behavioral rules or .claude/rules/ (committed to git) for team-wide rules." >&2
exit 2
