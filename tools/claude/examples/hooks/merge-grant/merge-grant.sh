#!/usr/bin/env bash
# Merge grant — a one-turn permission to merge a PR, armed only by the user's own prompt.
#
# UserPromptSubmit hook. A prompt that asks for a merge writes a grant for this session; every
# other prompt deletes it, so a grant lives for exactly one user turn. destructive-guard.sh reads
# the grant and turns a merge from a hard block into a permission prompt only while it is armed.
# Without this hook no grant is ever written, and every merge stays a hard block.
#
# Register in settings.json:
# "UserPromptSubmit": [{ "matcher": "", "hooks": [{ "type": "command", "command": "/path/to/merge-grant.sh" }] }]
#
# Requires: jq. Grants live in ${CLAUDE_MERGE_GRANT_DIR:-$HOME/.claude/merge-grants}/<session>.json;
# destructive-guard.sh reads the same variable.

GRANT_DIR="${CLAUDE_MERGE_GRANT_DIR:-$HOME/.claude/merge-grants}"
TTL=7200  # backstop for a turn that outlives its user: a long CI wait, a session resumed later

INPUT=$(cat)
command -v jq >/dev/null 2>&1 || exit 0
SESSION=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
PROMPT=$(printf '%s' "$INPUT" | jq -r '.prompt // empty' 2>/dev/null)

# The session id becomes a file name, so anything that could leave the directory arms nothing.
case "$SESSION" in ''|*[!A-Za-z0-9_-]*) exit 0 ;; esac

# A background-task notification is not the user speaking: it neither grants nor revokes.
case "$PROMPT" in *'<task-notification>'*) exit 0 ;; esac

# see: tools/claude/examples/hooks/merge-grant/README.md § What arms it
asks_to_merge() {
  printf '%s' "$PROMPT" | LC_ALL=C sed -e "s/’/'/g" | LC_ALL=C tr '[:upper:]' '[:lower:]' \
    | LC_ALL=C tr '\t\n' ' .' | LC_ALL=C sed -e "s/[^a-z' ]/ . /g" | LC_ALL=C tr -s ' ' '\n' | awk -v q="'" '
      BEGIN { n = split("don" q "t dont not never no without", w, " "); for (i = 1; i <= n; i++) neg[w[i]] = 1 }
      { gsub("^" q "+|" q "+$", "") }
      $0 == "" { next }
      $0 == "merge" && !(prev in neg) { found = 1 }
      $0 != "yet" { prev = $0 }
      END { exit !found }'
}

FILE="${GRANT_DIR}/${SESSION}.json"
if [ -n "$PROMPT" ] && asks_to_merge; then
  mkdir -p "$GRANT_DIR" 2>/dev/null || exit 0
  NOW=$(date +%s)
  TMP="${FILE}.tmp.$$"
  jq -nc --arg p "$(printf '%s' "$PROMPT" | tr '\n' ' ' | cut -c1-160)" \
         --argjson a "$NOW" --argjson e "$((NOW + TTL))" \
    '{armed_at: $a, expires_at: $e, prompt: $p}' > "$TMP" && mv -f "$TMP" "$FILE"
  jq -n '{hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext:
    "MERGE GRANT armed for this turn: a merge raises a permission prompt instead of a hard block. Merge only the PRs this message names. If mapping the request to specific PRs takes interpretation (a range, \"the ones above\", a list from an earlier turn), confirm the exact list before the first merge."}}'
else
  rm -f "$FILE"
fi
exit 0
