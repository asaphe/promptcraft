#!/usr/bin/env bash
# Stop hook — once the statusline flags this session over its context budget, block one turn end for a handoff.
# Flag writer, budget, install and output contract: see README.md in this directory.

# Runs on every turn end, so the no-flag path uses shell builtins only.
IFS= read -r -d '' INPUT || true
SESSION_ID=""
[[ $INPUT =~ \"session_id\"[[:space:]]*:[[:space:]]*\"([A-Za-z0-9_-]+)\" ]] && SESSION_ID=${BASH_REMATCH[1]}
[ -n "$SESSION_ID" ] || exit 0
FLAG="${CLAUDE_CONTEXT_BUDGET_DIR:-$HOME/.claude/context-budget}/${SESSION_ID}"
[ -f "$FLAG" ] || exit 0
# A prior Stop hook already blocked this yield; never chain, retry at the next turn end.
[[ $INPUT =~ \"stop_hook_active\"[[:space:]]*:[[:space:]]*true ]] && exit 0
# noclobber makes the claim atomic, so a declined handoff never re-prompts and two racing stops cannot both block.
( set -o noclobber; : > "${FLAG}.handled" ) 2>/dev/null || exit 0

read -r TOKENS BUDGET < "$FLAG" || true
[[ $TOKENS =~ ^[0-9]+$ ]] || TOKENS=0
[[ $BUDGET =~ ^[0-9]+$ ]] || BUDGET=0
# Fixed text plus integers only, so the JSON needs no escaping and the hook needs no jq.
REASON="CONTEXT BUDGET: this session is at ~$(( TOKENS / 1000 ))k context tokens, past its $(( BUDGET / 1000 ))k budget. Do not start a new step and do not /compact. 1) Write a self-contained handoff to a file outside the repository (for example ~/.claude/handoffs/<slug>.md): the objective, verified state, decisions made, remaining work, evidence and file paths, approval limits, the stop point, and any question you just asked. 2) Ask the user whether to continue in a fresh session, and wait for the answer. 3) Either way, end with the handoff path and the line 'read <path> and continue', which a new session can be started on."
printf '{"decision":"block","reason":"%s"}\n' "$REASON"
