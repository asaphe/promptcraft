#!/usr/bin/env bash
# Runs Claude Code Bash hooks under Codex in a fixed order, failing closed. see: tools/codex/shared-hooks.md § The dispatcher

set -u

HOOKS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
INPUT=$(cat)

# Without jq the event is unreadable, and any exit but 2-with-a-reason lets Codex run the command.
command -v jq >/dev/null 2>&1 || { echo "bash-hook-dispatcher: jq not on PATH, failing closed" >&2; exit 2; }

# Order is run order, and the first block wins.
PRE_HOOKS=(destructive-guard/destructive-guard.sh pr-create-guard/pr-create-guard.sh)
POST_HOOKS=(post-push-hygiene/post-push-hygiene.sh)

# Codex blocks only on exit 2 WITH a stderr reason, or an explicit deny; every other outcome runs the tool.
block() {
  echo "bash-hook-dispatcher: $1" >&2
  exit 2
}

# An event it cannot read may be a PreToolUse it cannot see, so it blocks rather than exit 1 and run the tool.
EVENT=$(printf '%s' "$INPUT" | jq -r '.hook_event_name // empty' 2>/dev/null)
case "$EVENT" in
  PreToolUse) HOOKS=("${PRE_HOOKS[@]}"); ALLOWED='["hookEventName","additionalContext","permissionDecision","permissionDecisionReason"]' ;;
  PostToolUse) HOOKS=("${POST_HOOKS[@]}"); ALLOWED='["hookEventName","additionalContext"]' ;;
  *) block "unsupported event '${EVENT:-<empty>}', failing closed" ;;
esac

CONTEXT=""
for HOOK in "${HOOKS[@]}"; do
  [ -f "$HOOKS_DIR/$HOOK" ] || block "child hook $HOOK is missing from $HOOKS_DIR"
  ERR=$(mktemp) || block "cannot allocate a stderr buffer"
  OUT=$(printf '%s' "$INPUT" | bash "$HOOKS_DIR/$HOOK" 2>"$ERR")
  CODE=$?
  REASON=$(head -c 4000 "$ERR")
  rm -f "$ERR"

  if [ "$CODE" -ne 0 ]; then
    [ "$CODE" -eq 2 ] && block "${REASON:-$HOOK exited 2 without a reason}"
    [ "$EVENT" = PreToolUse ] || { echo "$HOOK exited $CODE: ${REASON}" >&2; exit 1; }
    block "$HOOK exited $CODE, failing closed: ${REASON}"
  fi
  [ -n "$OUT" ] || continue

  if ! printf '%s' "$OUT" | jq -e --arg ev "$EVENT" --argjson allowed "$ALLOWED" '
        type == "object" and (keys - ["hookSpecificOutput"]) == []
        and .hookSpecificOutput.hookEventName == $ev
        and ((.hookSpecificOutput | keys) - $allowed) == []' >/dev/null 2>&1; then
    block "$HOOK returned output Codex cannot honour: $(printf '%s' "$OUT" | head -c 300)"
  fi

  DECISION=$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.permissionDecision // empty')
  WHY=$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty')
  case "$DECISION" in
    ''|allow) ;;
    deny) block "${WHY:-$HOOK denied the command}" ;;
    # Codex PreToolUse cannot prompt, so a passed-through "ask" would run the command unasked.
    *) block "$HOOK asked for confirmation ($DECISION), which a Codex PreToolUse hook cannot prompt for. ${WHY}" ;;
  esac

  C=$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.additionalContext // empty')
  [ -z "$C" ] || CONTEXT="${CONTEXT:+${CONTEXT}

}${C}"
done

[ -z "$CONTEXT" ] || jq -n --arg ev "$EVENT" --arg c "$CONTEXT" \
  '{hookSpecificOutput: {hookEventName: $ev, additionalContext: $c}}'
exit 0
