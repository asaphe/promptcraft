#!/usr/bin/env bash
# Per-turn grants — permission to merge a PR, open one or dispatch a CI run, armed only by the user's own words.
#
# UserPromptSubmit: a prompt that asks for an action writes that action's grant for this session;
# a bare affirmation ("yes", "go") renews a live `pr` or `dispatch` grant, and arms `dispatch` when
# the agent's last question proposed one; any other prompt that does not ask again deletes it.
# PostToolUse on AskUserQuestion: a menu answer that asks for a PR or a dispatch, or agrees to a
# question that proposed one, arms `pr` or `dispatch` — never `merge`. destructive-guard.sh reads
# the grants. `merge` turns a merge from a hard block into a permission prompt; `pr` drops the
# permission prompt on `gh pr create`; `dispatch` drops it on `gh workflow run`, `gh run rerun|cancel`
# and a `/dispatches` call. Without this hook no grant is ever written: every merge stays a hard
# block, and every `gh pr create` and dispatch asks.
#
# Register in settings.json:
# "UserPromptSubmit": [{ "matcher": "", "hooks": [{ "type": "command", "command": "/path/to/merge-grant.sh" }] }]
# "PostToolUse": [{ "matcher": "AskUserQuestion", "hooks": [{ "type": "command", "command": "/path/to/merge-grant.sh" }] }]
#
# Requires: jq, perl. Grants live in ${CLAUDE_MERGE_GRANT_DIR:-$HOME/.claude/merge-grants}:
# <session>.json for merge, <session>.<action>.json for the others. destructive-guard.sh reads the same variable.

GRANT_DIR="${CLAUDE_MERGE_GRANT_DIR:-$HOME/.claude/merge-grants}"
TTL=7200  # backstop for a turn that outlives its user: a long CI wait, a session resumed later
ACTIONS="merge pr dispatch"

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
asks_for() { # action, text, "label" when the text is a menu option a user picked
  words_ask_for "$1" "$(request_words "$2")" "${3:-}"
}

# The token stream asks_for parses, one word per line; callers checking several actions compute it once.
request_words() { # text
  printf '%s' "$1" | LC_ALL=C sed -e "s/’/'/g" -e "s/‘/'/g" -e "s/\`/'/g" | LC_ALL=C tr '[:upper:]' '[:lower:]' \
    | LC_ALL=C tr '\t\n' ' .' | LC_ALL=C sed -e "s/[.;!?]/ . /g" -e "s/[,()]/ , /g" -e "s/:/ : /g" \
      -e "s/pull[^a-z]*requests*/ pr /g" -e "s/^prs* *[#-]* *[0-9][0-9]*/ prref /" -e "s/\([^a-z]\)prs* *[#-]* *[0-9][0-9]*/\1 prref /g" \
      -e "s/merge[-_]\([a-z]\)/mergename\1/g" \
      -e "s/workflow[-_]dispatch/dispatchname/g" -e "s/repository[-_]dispatch/dispatchname/g" -e "s/dispatch[-_]\([a-z]\)/dispatchname\1/g" \
      -e "s/re-run/rerun/g" -e "s/re-trigger/retrigger/g" -e "s/re-dispatch/redispatch/g" \
      -e "s/[^a-z'.,: ]/ /g" \
    | LC_ALL=C tr -s ' ' '\n'
}

words_ask_for() { # action, request_words output, label
  printf '%s\n' "$2" | awk -v q="'" -v act="$1" -v label="${3:-}" '
      BEGIN { n = split("dont not never without cannot cant wont shouldnt couldnt wouldnt", w, " "); for (i = 1; i <= n; i++) neg[w[i]] = 1
              n = split("a an the this that these those my our your its their both another separate", w, " "); for (i = 1; i <= n; i++) det[w[i]] = 1
              n = split("a an the this that these those my our your its their another any each every", w, " "); for (i = 1; i <= n; i++) ndet[w[i]] = 1
              n = split("do finish complete perform run start", w, " "); for (i = 1; i <= n; i++) doer[w[i]] = 1
              n = split("ok okay yes yeah yep no sure great good fine thanks please alright cool perfect lgtm", w, " "); for (i = 1; i <= n; i++) intj[w[i]] = 1
              n = split("keep keeps kept leave leaves left", w, " "); for (i = 1; i <= n; i++) hold[w[i]] = 1
              n = split("of on about from with by per in into for to at when after before across over under", w, " "); for (i = 1; i <= n; i++) stop[w[i]] = 1
              n = split("is are was were need needs look looks have has", w, " "); for (i = 1; i <= n; i++) cop[w[i]] = 1
              n = split("you we i they he she someone anyone somebody anybody", w, " "); for (i = 1; i <= n; i++) subj[w[i]] = 1
              seg_intj = 1; clause_intj = 1 }
      { gsub("^" q "+|" q "+$", "") }
      $0 == "" { next }
      $0 == "." || $0 == "but" { if (tent || (label != "" && pending)) found = 1; tent = 0; asked = 0; negated = 0; prev = ""; lead_ok = 0; seg_intj = 1; seg_n = 0; clause_intj = 1; pr_verb = 0; opening = 0; fresh = 0; pending = 0; next }
      $0 == "," || $0 == ":" { if (label == "answer" && pending) found = 1; if ($0 == ":" && label != "answer") tent = 0; pr_verb = 0; opening = 0; fresh = 0; pending = 0; if (seg_n > 0) lead_ok = seg_intj; seg_intj = 1; seg_n = 0; prev = ","; next }
      { seg_n++; lead_intj = clause_intj; if (!($0 in intj)) { seg_intj = 0; clause_intj = 0 } }
      act == "pr" && pending { if (!(($0 in neg) || $0 ~ ("n" q "t$") || ($0 in cop))) tent = 1; pending = 0 }
      after_did && ($0 in subj) && label == "" { asked = 1 }
      { after_did = ($0 == "did") }
      $0 in neg || $0 ~ ("n" q "t$") { negated = 1 }
      act == "merge" && $0 == "merge" && !negated && prev != "no" && !asked && !((prev in ndet) && !(prev2 in doer)) && !(prev == "to" && prev2 == "ready") { found = 1 }
      act == "dispatch" && ($0 == "dispatch" || $0 == "rerun" || $0 == "retrigger" || $0 == "redispatch") && !negated && prev != "no" && !asked && !((prev in ndet) && !(prev2 in doer)) && !(prev == "to" && prev2 == "ready") { found = 1 }
      act == "pr" && pr_verb > 0 && ($0 in stop) { pr_verb = 0; opening = 0 }
      act == "pr" && opening { if (!($0 in det)) pr_verb = 0; opening = 0 }
      act == "pr" && fresh && pr_verb > 0 && ($0 == "pr" || $0 == "prs") { if (held_open) pending = 1; else tent = 1; pr_verb = 0 }
      act == "pr" && pr_verb > 0 && ($0 == "pr" || $0 == "prs") { found = 1 }
      act == "pr" && pr_verb > 0 { pr_verb-- }
      { fresh = 0 }
      act == "pr" && ($0 == "open" || $0 == "create" || $0 == "raise") && !negated && !asked && prev != "no" && !($0 == "open" && (prev in hold)) { pr_verb = 4; fresh = 1; held_open = ($0 == "open"); opening = ($0 == "open" && prev != "" && !lead_intj && !(prev == "," && lead_ok)) }
      { prev2 = prev; prev = $0 }
      END { if (tent || (label != "" && pending)) found = 1; exit !found }'
}

# see: tools/claude/examples/hooks/merge-grant/README.md § Bare affirmations
is_affirmation() { # text: a menu answer or a typed prompt
  printf '%s' "$1" | LC_ALL=C tr '[:upper:]' '[:lower:]' | sed -e 's/(recommended)//g' \
    | LC_ALL=C tr -c "a-z'\n" ' ' | LC_ALL=C tr -s ' ' '\n' | awk '
      BEGIN { n = split("yes y yep yeah ok okay sure approve approved confirm confirmed proceed go ahead do it please just now", w, " "); for (i = 1; i <= n; i++) ok[w[i]] = 1 }
      $0 == "" { next }
      { words++ }
      !($0 in ok) { other = 1 }
      END { exit !(words > 0 && !other) }'
}

# Only questions: a status line that merely mentions a dispatch is not what a bare "go" answers.
last_assistant_questions() { # transcript path
  [ -f "$1" ] || return 0
  tail -n 400 "$1" | jq -rRn '[inputs | fromjson? | select(.type == "assistant" and (.isSidechain | not))
      | .message.content | if type == "array" then (map(select(.type == "text") | .text) | join(" ")) else (. // "" | tostring) end
      | select(length > 0)] | last // ""' 2>/dev/null | tail -c 2000 \
    | perl -0777 -ne 'print join(" . ", grep { /\?\s*$/ } split /(?<=[.!?])\s+|\n+/), "\n"'
}

live() { # action
  local expires
  expires=$(jq -r '.expires_at // 0' "$(grant_file "$1")" 2>/dev/null) || return 1
  case "$expires" in ''|*[!0-9]*) return 1 ;; esac
  [ "$(date +%s)" -lt "$expires" ]
}

grant_context() { # action
  case "$1" in
    merge) printf '%s' "MERGE GRANT armed for this turn: a merge raises a permission prompt instead of a hard block. Merge only the PRs this message names. If mapping the request to specific PRs takes interpretation (a range, \"the ones above\", a list from an earlier turn), confirm the exact list before the first merge." ;;
    pr) printf '%s' "PR GRANT armed for this turn: \`gh pr create\` runs without destructive-guard's permission prompt; pr-create-guard still checks it. Open only the PR this message asks for." ;;
    dispatch) printf '%s' "DISPATCH GRANT armed for this turn: \`gh workflow run\`, \`gh run rerun\`, \`gh run cancel\` and a \`gh api .../dispatches\` call run without destructive-guard's permission prompt. Dispatch only the workflow this exchange named, on the ref and inputs stated; \`gh run delete\` still asks." ;;
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

# A menu pick is a tool result, not a prompt: it arms pr or dispatch and clears nothing. Merge needs typed words.
if [ "$EVENT" = "PostToolUse" ]; then
  [ "$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)" = "AskUserQuestion" ] || exit 0
  PAIRS=$(printf '%s' "$INPUT" | jq -r '((.tool_response | objects | .answers) // .tool_input.answers // {})
    | to_entries[] | [.key, (.value | tostring)] | @tsv' 2>/dev/null) || exit 0
  # Each pair's words are computed once, not once per action.
  QS=(); ANS=(); QW=(); AW=(); PRQ=()
  while IFS=$'\t' read -r question answer; do
    [ -n "$answer" ] || continue
    alabel=answer
    printf '%s' "$question" | LC_ALL=C grep -qiE '(^|[^a-z])(prs|pull requests)([^a-z]|$)' && alabel=""
    QS+=("$question"); ANS+=("$answer"); QW+=("$(request_words "$question")"); AW+=("$(request_words "$answer")"); PRQ+=("$alabel")
  done <<<"$PAIRS"
  for a in pr dispatch; do
    i=0
    while [ "$i" -lt "${#QS[@]}" ]; do
      alabel=answer; [ "$a" = pr ] && alabel=${PRQ[$i]}
      if words_ask_for "$a" "${AW[$i]}" "$alabel" || { words_ask_for "$a" "${QW[$i]}" question && is_affirmation "${ANS[$i]}"; }; then
        arm "$a" "menu: ${QS[$i]} -> ${ANS[$i]}" && CONTEXT="${CONTEXT:+${CONTEXT} }$(grant_context "$a")"
        break
      fi
      i=$((i + 1))
    done
  done
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
if [ -n "$PROMPT" ] && [ -z "${OWN//[[:space:]]/}" ]; then
  exit 0
fi

AFFIRM=""; PROPOSAL=""
if [ -n "$OWN" ] && is_affirmation "$OWN"; then
  AFFIRM=1
  PROPOSAL=$(last_assistant_questions "$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)")
fi

# see: tools/claude/examples/hooks/merge-grant/README.md § Bare affirmations — merge keeps the typed-words rule
# This hook runs on every prompt, so the prompt is normalized once for all actions.
OWN_WORDS=""; [ -z "$OWN" ] || OWN_WORDS=$(request_words "$OWN")
for a in $ACTIONS; do
  if [ -n "$OWN" ] && words_ask_for "$a" "$OWN_WORDS"; then
    arm "$a" "$OWN" && CONTEXT="${CONTEXT:+${CONTEXT} }$(grant_context "$a")"
  elif [ -n "$AFFIRM" ] && [ "$a" != merge ] && live "$a"; then
    arm "$a" "$(jq -r '.prompt // ""' "$(grant_file "$a")" 2>/dev/null)" && CONTEXT="${CONTEXT:+${CONTEXT} }$(grant_context "$a")"
  elif [ -n "$AFFIRM" ] && [ "$a" = dispatch ] && [ -n "$PROPOSAL" ] && asks_for dispatch "$PROPOSAL" question; then
    arm dispatch "affirmed: ${OWN} -> $(printf '%s' "$PROPOSAL" | tail -c 120)" && CONTEXT="${CONTEXT:+${CONTEXT} }$(grant_context dispatch)"
  else
    f=$(grant_file "$a")
    if [ -e "$f" ] || [ -L "$f" ]; then rm -f "$f"; fi
  fi
done
emit UserPromptSubmit "$CONTEXT"
exit 0
