#!/usr/bin/env bash
# SessionStart guard: re-pin model/effort so a persisted /model or /effort pick cannot silently replace the intended defaults.
# Register in settings.json:
# "SessionStart": [{ "hooks": [{ "type": "command", "command": "$HOME/.claude/hooks/model-effort-pin-guard/model-effort-pin-guard.sh" }] }]
set -euo pipefail

PIN_MODEL="${PIN_MODEL:-opus}"
PIN_EFFORT="${PIN_EFFORT:-medium}"
# /effort persists under modelSettings.<model>.effortLevel, so per-model effort defaults are pinned too.
DEFAULT_PINS='{"claude-opus-5-5":"medium","claude-fable-5-1":"high","claude-sonnet-5-5":"medium"}'
PIN_MODEL_EFFORTS="${PIN_MODEL_EFFORTS:-$DEFAULT_PINS}"
SETTINGS="${PIN_GUARD_SETTINGS:-$HOME/.claude/settings.json}"

command -v jq >/dev/null 2>&1 || exit 0
[ -f "$SETTINGS" ] || exit 0

CUR_MODEL=$(jq -r '.model // ""' "$SETTINGS" 2>/dev/null || echo "")
CUR_EFFORT=$(jq -r '.effortLevel // ""' "$SETTINGS" 2>/dev/null || echo "")
MODEL_DRIFT=$(jq -r --argjson pins "$PIN_MODEL_EFFORTS" \
  '[($pins | to_entries[]) as $p | select((.modelSettings[$p.key].effortLevel // "") != $p.value) | "\($p.key)=\($p.value) (was \(.modelSettings[$p.key].effortLevel // "unset"))"] | join(", ")' \
  "$SETTINGS" 2>/dev/null || echo "")

# No drift: leave the file (and its git state) untouched.
[ "$CUR_MODEL" = "$PIN_MODEL" ] && [ "$CUR_EFFORT" = "$PIN_EFFORT" ] && [ -z "$MODEL_DRIFT" ] && exit 0

TMP=$(mktemp)
if jq --arg m "$PIN_MODEL" --arg e "$PIN_EFFORT" --argjson pins "$PIN_MODEL_EFFORTS" \
  '.model=$m | .effortLevel=$e | reduce ($pins | to_entries[]) as $p (.; .modelSettings[$p.key].effortLevel = $p.value)' \
  "$SETTINGS" > "$TMP" 2>/dev/null && [ -s "$TMP" ]; then
  cat "$TMP" > "$SETTINGS"   # redirect writes THROUGH a symlink, preserving a dotfiles link
  rm -f "$TMP"
  MSG="Model/effort default guard: restored model=${PIN_MODEL} (was '${CUR_MODEL:-unset}'), effortLevel=${PIN_EFFORT} (was '${CUR_EFFORT:-unset}')${MODEL_DRIFT:+, modelSettings ${MODEL_DRIFT}} in settings.json, likely from a persisted /model or /effort pick. Session-only switches are unaffected. To change the real default, set PIN_MODEL / PIN_EFFORT for this hook."
  jq -n --arg ctx "$MSG" '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$ctx}}'
else
  rm -f "$TMP"
fi
exit 0
