#!/usr/bin/env bash
# PostToolUse:Bash — a command that returns nothing (or a scanner that reports a confident
# zero) produces output byte-identical to the same command whose file list, glob, or pathspec
# silently collapsed. Nudges for a control probe before that emptiness is read as a finding.
# Registration JSON: README.md. Requires: jq, perl.
#
# PostToolUse fires only on the success path — the Bash tool throws on a non-zero exit, except
# for grep/rg/find/diff/test, whose exit 1 it reclassifies as a result. So the event itself
# carries the "and exit 0" half of the predicate; the hook never has to test it.
#
# Deliberately does not source hook-diag.sh: this runs on every Bash call, and with
# HOOK_DIAG_LOG_ALLOWS=1 that would halve the allow log's retention window for every other hook.

set -uo pipefail

LOG="${NULL_RESULT_PROBE_LOG:-$HOME/.claude/local/null-result-probe.log}"
LOG_MAX=1048576

log_line() {
  [ -n "${CLAUDE_HOOK_FIXTURE_RUN:-}" ] && return 0
  local category="$2"
  case "$category" in
    backgrounded|no_output_expected|has_output|stdout_redirected|no_construct_empty|no_construct_zero|empty|zero) ;;
    *) category=unknown ;;
  esac
  (
    umask 077
    mkdir -p "$(dirname "$LOG")" 2>/dev/null || exit 0
    if [ -f "$LOG" ] && [ "$(wc -c < "$LOG" 2>/dev/null | tr -d ' ')" -gt "$LOG_MAX" ]; then
      mv "$LOG" "${LOG}.prev" 2>/dev/null || exit 0
    fi
    printf '{"ts":"%s","hook":"null-result-probe","event":"%s"}\n' \
      "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$category" >> "$LOG"
  ) 2>/dev/null || :
  return 0
}

# Both streams count: the executor already merges them into stdout for most commands, and a
# command that spoke only on stderr has not returned nothing. Summed rather than concatenated —
# stdout reaches 64 MB, and this runs on every Bash call, so the copy is not affordable.
FIELDS=$(jq -r '
  (.tool_response // {}) as $r
  | (if ($r | type) == "object" then ($r.stdout // "") else "" end) as $so
  | (if ($r | type) == "object" then ($r.stderr // "") else "" end) as $se
  | [ ((.tool_input.command // "") | @base64),
      (($so | length) + ($se | length)),
      ((if ($so | length) > 0 then $so[0:400] else $se[0:400] end) | @base64),
      (if ($r | type) == "object" and ($r.noOutputExpected // false) == true then 1 else 0 end),
      (if ($r | type) == "object" and ((($r.backgroundTaskId // "") | tostring) | length) > 0
       then 1 else 0 end)
    ] | @tsv' 2>/dev/null) || exit 0
[ -n "$FIELDS" ] || exit 0

IFS=$'\t' read -r CMD_B64 OUT_LEN OUT_HEAD_B64 NO_OUTPUT_EXPECTED BACKGROUNDED <<<"$FIELDS"
OUT_LEN="${OUT_LEN:-1}"
NO_OUTPUT_EXPECTED="${NO_OUTPUT_EXPECTED:-0}"
BACKGROUNDED="${BACKGROUNDED:-0}"

CMD=$(printf '%s' "${CMD_B64:-}" | base64 -d 2>/dev/null)
[ -n "$CMD" ] || exit 0

[ "$BACKGROUNDED" = "1" ] && { log_line 0 backgrounded; exit 0; }
[ "$NO_OUTPUT_EXPECTED" = "1" ] && { log_line 0 no_output_expected; exit 0; }

OUT_HEAD=$(printf '%s' "${OUT_HEAD_B64:-}" | base64 -d 2>/dev/null)

# A scanner's "found nothing" line is as ambiguous as no line at all, and it is the more
# dangerous half: it reads as a completed clean scan. Extend this list when a tool whose
# zero-output is indistinguishable from a failed invocation turns up.
ZERO_FINDING='0 file\(s\) with matches|no matches found|found 0 |(^|[^0-9])0 (findings|issues|problems|matches|results|files)|no (issues|problems|findings|results|matches) found|^[[:space:]]*0[[:space:]]*$'

ARM=""
if [ "$OUT_LEN" -eq 0 ] || { [ "$OUT_LEN" -le 400 ] && [ -z "${OUT_HEAD//[[:space:]]/}" ]; }; then
  ARM="empty"
elif [ "$OUT_LEN" -le 400 ] && printf '%s' "$OUT_HEAD" | grep -qiE "$ZERO_FINDING"; then
  ARM="zero"
else
  log_line 0 has_output
  exit 0
fi

# strip_quoted_args blanks quoted DATA but preserves a $(...) as code; dropping the surviving
# quote spans afterwards is what leaves only genuinely unquoted text to match against. Without
# the helper the raw command is matched instead — an extra nudge is the safe way to be wrong,
# a silent skip is not.
CMD_U="$CMD"
# shellcheck source=/dev/null  # runtime-only source
if source "$(dirname "$0")/../_lib/strip-cmd.sh" 2>/dev/null; then
  CMD_U=$(strip_quoted_args "$(strip_cmd "$CMD")" \
    | perl -0777 -pe 's/\x27[^\x27]*\x27//g; s/"(?:\\.|[^"\\])*"//g' 2>/dev/null)
  [ -n "$CMD_U" ] || CMD_U="$CMD"
fi

# Redirected stdout is empty by construction. `2>` is deliberately not matched here: a command
# whose stderr was discarded is a stronger candidate for this nudge, not a weaker one.
if printf '%s' "$CMD_U" | grep -qE '(^|[[:space:]])(1?>>?|&>)[[:space:]]*[^|&>[:space:]]|\|[[:space:]]*tee([[:space:]]|$)'; then
  log_line 0 stdout_redirected
  exit 0
fi

WHY=""
add_why() { WHY="${WHY:+$WHY; }$1"; }

# Matched against $CMD, not $CMD_U: the label lives inside a quoted echo, which strip_quoted_args
# blanks by design. Arms on the label alone with no construct required -- a control probe that has
# nothing suspicious in it is exactly the case the construct checks below cannot reach.
printf '%s' "$CMD" | grep -qiE 'control[- ]?probe|===[[:space:]]*control|control:|must[- ](print|produce|output|emit)|known[- ]positive' \
  && add_why 'a self-declared control probe, whose verdict is known in advance: it MUST produce output, so silence means the control itself is broken'

# shellcheck disable=SC2016  # `$` and backticks below are literal message text and regex, not expansions
printf '%s' "$CMD_U" | grep -qE '(^|[[:space:]])git([[:space:]]|$)' \
  && printf '%s' "$CMD_U" | grep -qE '[[:space:]]--[[:space:]]' \
  && add_why 'a git pathspec after `--` (a path that matches nothing returns exactly this)'

# shellcheck disable=SC2016
printf '%s' "$CMD_U" | grep -qE '(^|[[:space:]])find([[:space:]])' \
  && printf '%s' "$CMD_U" | grep -qE '(^|[[:space:]])/tmp([[:space:]]|$)' \
  && ! printf '%s' "$CMD_U" | grep -qE '(^|[[:space:]])-L([[:space:]]|$)' \
  && add_why '`find` on an unresolved /tmp (a symlink on macOS, which find will not follow without -L)'

# shellcheck disable=SC2016
printf '%s' "$CMD_U" | grep -qE '(^|[[:space:]])\$(\(|\{?[A-Za-z_])' \
  && add_why 'an unquoted expansion (zsh does not word-split it, so a multi-value variable arrives as ONE argument)'

printf '%s' "$CMD_U" | grep -qE '(^|[[:space:]])[^[:space:]]*/[^[:space:]]*[*?][^[:space:]]*' \
  && add_why 'an unquoted path glob'

if [ -z "$WHY" ]; then
  log_line 0 "no_construct_${ARM}"
  exit 0
fi

if [ "$ARM" = "empty" ]; then
  CTX="NULL-RESULT PROBE — this command returned no output and did not fail, and it contains ${WHY}. An empty result here is byte-identical to what the same command returns when that construct silently resolved to nothing, so it is not yet evidence of anything. Before this emptiness becomes a conclusion, run a control that MUST produce output — echo the argument list the command actually received, drop the filter, or quote the expansion. Rule: the shell-traps rule (rules/general/shell-traps.md)."
else
  CTX="NULL-RESULT PROBE — this scan reported zero findings, and the command contains ${WHY}. A scanner handed a collapsed file list prints the same confident zero it prints for a genuinely clean tree, so this output does not yet show the scan ran over the files you meant. Confirm how many files it actually opened before treating the result as clean. Rule: the shell-traps rule (rules/general/shell-traps.md)."
fi

log_line 1 "$ARM"
jq -n --arg ctx "$CTX" \
  '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $ctx}}'
