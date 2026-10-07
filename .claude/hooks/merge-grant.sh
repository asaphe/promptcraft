#!/usr/bin/env bash
# Per-turn grants — permission to merge a PR or open one, armed only by the user's own words.
#
# UserPromptSubmit: a prompt that asks for an action writes that action's grant for this session;
# the user's next prompt that does not ask again deletes it. PostToolUse on AskUserQuestion: a menu
# answer that asks for a PR, or agrees to a question that proposed one, arms `pr` — never `merge`.
# destructive-guard.sh reads the grants. `merge` turns a merge from a hard block into a permission
# prompt; `pr` drops the permission prompt on `gh pr create`. Without this hook no grant is ever
# written: every merge stays a hard block and every `gh pr create` asks.
#
# Register in settings.json:
# "UserPromptSubmit": [{ "matcher": "", "hooks": [{ "type": "command", "command": "/path/to/merge-grant.sh" }] }]
# "PostToolUse": [{ "matcher": "AskUserQuestion", "hooks": [{ "type": "command", "command": "/path/to/merge-grant.sh" }] }]
#
# Requires: jq, perl. Grants live in ${CLAUDE_MERGE_GRANT_DIR:-$HOME/.claude/merge-grants}:
# <session>.json for merge, <session>.pr.json for pr. destructive-guard.sh reads the same variable.

GRANT_DIR="${CLAUDE_MERGE_GRANT_DIR:-$HOME/.claude/merge-grants}"
TTL=7200  # backstop for a turn that outlives its user: a long CI wait, a session resumed later
ACTIONS="merge pr"

INPUT=$(cat)
command -v jq >/dev/null 2>&1 && command -v perl >/dev/null 2>&1 || exit 0
SESSION=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
EVENT=$(printf '%s' "$INPUT" | jq -r '.hook_event_name // empty' 2>/dev/null)

# The session id becomes a file name, so anything that could leave the directory arms nothing.
case "$SESSION" in ''|*[!A-Za-z0-9_-]*) exit 0 ;; esac

# merge keeps the unsuffixed name, so a guard written before the pr grant still finds it.
grant_file() { # action
  if [ "$1" = merge ]; then printf '%s/%s.json' "$GRANT_DIR" "$SESSION"; else printf '%s/%s.%s.json' "$GRANT_DIR" "$SESSION" "$1"; fi
}

# see: tools/claude/examples/hooks/merge-grant/README.md § What arms it
asks_for() { # action, text
  printf '%s' "$2" | LC_ALL=C sed -e "s/’/'/g" | LC_ALL=C tr '[:upper:]' '[:lower:]' \
    | LC_ALL=C tr '\t\n' ' .' | LC_ALL=C sed -e "s/[.,;:!?()]/ . /g" -e "s/[^a-z'. ]/ /g" \
    | LC_ALL=C tr -s ' ' '\n' | awk -v q="'" -v act="$1" '
      BEGIN { n = split("don" q "t dont not never without", w, " "); for (i = 1; i <= n; i++) neg[w[i]] = 1 }
      { gsub("^" q "+|" q "+$", "") }
      $0 == "" { next }
      $0 == "." || $0 == "but" { negated = 0; prev = ""; pr_verb = 0; next }
      $0 in neg { negated = 1 }
      act == "merge" && $0 == "merge" && !negated && prev != "no" { found = 1 }
      act == "pr" && pr_verb > 0 && ($0 == "pr" || $0 == "prs" || $0 == "pull") { found = 1 }
      act == "pr" && pr_verb > 0 { pr_verb-- }
      act == "pr" && ($0 == "open" || $0 == "create" || $0 == "raise") && !negated && prev != "no" { pr_verb = 4 }
      { prev = $0 }
      END { exit !found }'
}

# see: tools/claude/examples/hooks/merge-grant/README.md § Menu answers
answer_consents() { # answer
  local a
  a=$(printf '%s' "$1" | LC_ALL=C tr '[:upper:]' '[:lower:]' | sed -e "s/’/'/g" -e 's/(recommended)//g')
  printf '%s' "$a" | grep -qE "(^|[^a-z'])(don'?t|do not|not|never|no|without|skip|hold|wait|later|cancel|stop|abort|decline|keep)([^a-z]|\$)" && return 1
  printf '%s' "$a" | grep -qE '^[[:space:]]*(yes|y|open|create|raise|proceed|go|approve|approved|confirm|ok|okay|sure|do it)([^a-z]|$)'
}

grant_context() { # action
  case "$1" in
    merge) printf '%s' "MERGE GRANT armed for this turn: a merge raises a permission prompt instead of a hard block. Merge only the PRs this message names. If mapping the request to specific PRs takes interpretation (a range, \"the ones above\", a list from an earlier turn), confirm the exact list before the first merge." ;;
    pr) printf '%s' "PR GRANT armed for this turn: \`gh pr create\` runs without destructive-guard's permission prompt; pr-create-guard still checks it. Open only the PR this message asks for." ;;
  esac
}

arm() { # action, excerpt
  local file tmp now
  file=$(grant_file "$1")
  mkdir -p "$GRANT_DIR" 2>/dev/null || return 1
  now=$(date +%s)
  tmp="${file}.tmp.$$"
  jq -nc --arg a "$1" --arg p "$(printf '%s' "$2" | tr '\n' ' ' | cut -c1-160)" \
         --argjson t "$now" --argjson e "$((now + TTL))" \
    '{action: $a, armed_at: $t, expires_at: $e, prompt: $p}' > "$tmp" && mv -f "$tmp" "$file"
}

emit() { # event, context
  [ -z "$2" ] || jq -nc --arg ev "$1" --arg c "$2" '{hookSpecificOutput: {hookEventName: $ev, additionalContext: $c}}'
}

CONTEXT=""

# A menu pick is a tool result, not a prompt: it arms pr and clears nothing. Merge needs typed words.
if [ "$EVENT" = "PostToolUse" ]; then
  [ "$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)" = "AskUserQuestion" ] || exit 0
  PAIRS=$(printf '%s' "$INPUT" | jq -r '((.tool_response | objects | .answers) // .tool_input.answers // {})
    | to_entries[] | [.key, (.value | tostring)] | @tsv' 2>/dev/null) || exit 0
  while IFS=$'\t' read -r question answer; do
    [ -n "$answer" ] || continue
    if asks_for pr "$answer" || { asks_for pr "$question" && answer_consents "$answer"; }; then
      arm pr "menu: ${question} -> ${answer}" && CONTEXT=$(grant_context pr)
      break
    fi
  done <<<"$PAIRS"
  emit PostToolUse "$CONTEXT"
  exit 0
fi

PROMPT=$(printf '%s' "$INPUT" | jq -r '.prompt // empty' 2>/dev/null)

# see: tools/claude/examples/hooks/merge-grant/README.md § Harness-injected blocks
if ! OWN=$(printf '%s' "$PROMPT" | perl -0777 -pe '
      s/<task-notification>.*?<\/task-notification>//gs;
      s/<agent-message\b[^>]*>.*?<\/agent-message>//gs;'); then
  for a in $ACTIONS; do rm -f "$(grant_file "$a")"; done
  exit 0
fi
if [ -n "$PROMPT" ] && [ -z "$(printf '%s' "$OWN" | tr -d '[:space:]')" ]; then
  exit 0
fi

for a in $ACTIONS; do
  if [ -n "$OWN" ] && asks_for "$a" "$OWN"; then
    arm "$a" "$OWN" && CONTEXT="${CONTEXT:+${CONTEXT} }$(grant_context "$a")"
  else
    rm -f "$(grant_file "$a")"
  fi
done
emit UserPromptSubmit "$CONTEXT"
exit 0
