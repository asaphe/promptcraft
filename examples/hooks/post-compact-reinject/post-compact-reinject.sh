#!/usr/bin/env bash
# SessionStart (matcher: compact) — re-injects key behavioral rules after context compaction.
# Plain stdout is added directly to Claude's context by SessionStart hooks.
#
# Why SessionStart and not PostCompact?
# PostCompact is a side-effects-only event — it cannot inject context into the conversation.
# SessionStart with matcher "compact" fires after compaction completes and its stdout
# is added directly to Claude's context window.

BRANCH=$(git branch --show-current 2>/dev/null || echo "unknown")

PR_INFO=""
if command -v gh &>/dev/null && [ "$BRANCH" != "main" ] && [ "$BRANCH" != "unknown" ]; then
  PR_NUM=$(gh pr view --json number -q '.number' 2>/dev/null || true)
  if [ -n "$PR_NUM" ]; then
    PR_STATE=$(gh pr view --json number,state,reviewDecision -q '"PR #\(.number) [\(.state)] review:\(.reviewDecision // "pending")"' 2>/dev/null || true)
    [ -n "$PR_STATE" ] && PR_INFO="- Active PR: $PR_STATE"
  fi
fi

echo "Post-compaction context refresh:"
echo "- Branch: $BRANCH"
[ -n "$PR_INFO" ] && echo "$PR_INFO"
# Customize: add your critical behavioral rules that tend to get lost during compaction
echo "- Key rules: <add project-specific rules that compaction tends to drop>"
