#!/usr/bin/env bash
# SessionStart (matcher: compact) — injects live git state after context compaction.
# Compaction loses dynamic state that always-loaded rules/CLAUDE.md can't restore.
# Plain stdout is added directly to Claude's context by SessionStart hooks.
#
# Why SessionStart and not PostCompact?
# PostCompact is a side-effects-only event — it cannot inject context into the conversation.
# SessionStart with matcher "compact" fires after compaction completes and its stdout
# is added directly to Claude's context window.
#
# What this does NOT re-inject (and why):
# - Behavioral rules → already in always-loaded .claude/rules/ and CLAUDE.md
# - Branch name alone → "Re-verify state" rule already instructs Claude to check
# - PR info → Claude can query with gh; rules already instruct re-verification
#
# What this DOES inject: dynamic git state that is dangerous to lose silently.

BRANCH=$(git branch --show-current 2>/dev/null || echo "unknown")

DIRTY=$(git status --short 2>/dev/null)
WORKTREES=$(git worktree list 2>/dev/null | grep -v "$(git rev-parse --show-toplevel 2>/dev/null)" || true)
STASH_COUNT=$(git stash list 2>/dev/null | wc -l | tr -d ' ')

HAS_OUTPUT=false

if [ -n "$DIRTY" ]; then
  HAS_OUTPUT=true
  echo "Post-compaction state:"
  echo "- Branch: $BRANCH"
  echo "- Uncommitted changes:"
  echo "$DIRTY" | head -20
fi

if [ -n "$WORKTREES" ]; then
  $HAS_OUTPUT || { echo "Post-compaction state:"; echo "- Branch: $BRANCH"; }
  HAS_OUTPUT=true
  echo "- Active worktrees:"
  echo "$WORKTREES"
fi

if [ "$STASH_COUNT" -gt 0 ] 2>/dev/null; then
  $HAS_OUTPUT || { echo "Post-compaction state:"; echo "- Branch: $BRANCH"; }
  HAS_OUTPUT=true
  echo "- Stashed changes: $STASH_COUNT"
fi

# Zero output when clean — no wasted tokens
