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
  printf '%s' "$2" | LC_ALL=C sed -e "s/’/'/g" -e "s/‘/'/g" -e "s/\`/'/g" | LC_ALL=C tr '[:upper:]' '[:lower:]' \
    | LC_ALL=C tr '\t\n' ' .' | LC_ALL=C sed -e "s/[.;!?]/ . /g" -e "s/[,:()]/ , /g" \
      -e "s/pull[^a-z]*requests*/ pr /g" -e "s/^prs* *#* *[0-9][0-9]*/ prref /" -e "s/\([^a-z]\)prs* *#* *[0-9][0-9]*/\1 prref /g" \
      -e "s/[^a-z'., ]/ /g" \
    | LC_ALL=C tr -s ' ' '\n' | awk -v q="'" -v act="$1" '
      BEGIN { n = split("dont not never without cannot cant wont shouldnt couldnt wouldnt", w, " "); for (i = 1; i <= n; i++) neg[w[i]] = 1
              n = split("a an the this that these those my our your its their both another separate", w, " "); for (i = 1; i <= n; i++) det[w[i]] = 1
              n = split("ok okay yes yeah yep no sure great good fine thanks please alright cool perfect lgtm", w, " "); for (i = 1; i <= n; i++) intj[w[i]] = 1
              n = split("keep keeps kept leave leaves left", w, " "); for (i = 1; i <= n; i++) hold[w[i]] = 1
              n = split("of on about from with by per in into", w, " "); for (i = 1; i <= n; i++) stop[w[i]] = 1
              seg_intj = 1; clause_intj = 1 }
      { gsub("^" q "+|" q "+$", "") }
      $0 == "" { next }
      $0 == "." || $0 == "but" { negated = 0; prev = ""; lead_ok = 0; seg_intj = 1; seg_n = 0; clause_intj = 1; pr_verb = 0; opening = 0; fresh = 0; pending = 0; next }
      $0 == "," { pr_verb = 0; opening = 0; fresh = 0; pending = 0; if (seg_n > 0) lead_ok = seg_intj; seg_intj = 1; seg_n = 0; prev = ","; next }
      { seg_n++; lead_intj = clause_intj; if (!($0 in intj)) { seg_intj = 0; clause_intj = 0 } }
      act == "pr" && pending { found = 1; pending = 0 }
      $0 in neg || $0 ~ ("n" q "t$") { negated = 1 }
      act == "merge" && $0 == "merge" && !negated && prev != "no" { found = 1 }
      act == "pr" && pr_verb > 0 && ($0 in stop) { pr_verb = 0; opening = 0 }
      act == "pr" && opening { if (!($0 in det)) pr_verb = 0; opening = 0 }
      act == "pr" && fresh && pr_verb > 0 && ($0 == "pr" || $0 == "prs") { pending = 1; pr_verb = 0 }
      act == "pr" && pr_verb > 0 && ($0 == "pr" || $0 == "prs") { found = 1 }
      act == "pr" && pr_verb > 0 { pr_verb-- }
      { fresh = 0 }
      act == "pr" && ($0 == "open" || $0 == "create" || $0 == "raise") && !negated && prev != "no" && !($0 == "open" && (prev in hold)) { pr_verb = 4; fresh = 1; opening = ($0 == "open" && prev != "" && !lead_intj && !(prev == "," && lead_ok)) }
      { prev = $0 }
      END { exit !found }'
}

# see: tools/claude/examples/hooks/merge-grant/README.md § Menu answers
answer_consents() { # answer
  printf '%s' "$1" | LC_ALL=C tr '[:upper:]' '[:lower:]' | sed -e 's/(recommended)//g' \
    | LC_ALL=C tr -c "a-z'\n" ' ' | LC_ALL=C tr -s ' ' '\n' | awk '
      BEGIN { n = split("yes y yep yeah ok okay sure approve approved confirm confirmed proceed go ahead do it please", w, " "); for (i = 1; i <= n; i++) ok[w[i]] = 1 }
      $0 == "" { next }
      { words++ }
      !($0 in ok) { other = 1 }
      END { exit !(words > 0 && !other) }'
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
      s/<agent-message\b[^>]*>.*?<\/agent-message>//gs;') \
   || printf '%s' "$OWN" | grep -qE '</?(task-notification|agent-message)'; then
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
