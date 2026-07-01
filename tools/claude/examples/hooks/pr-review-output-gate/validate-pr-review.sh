#!/usr/bin/env bash
# Validates the /pr-review dismissal log; exit 0 = compliant, 1 = violation(s) to stderr. Schema + rationale: see README.md.
set -euo pipefail

PR="${1:?usage: validate-pr-review.sh <pr-number> [<log-file>]}"
LOG="${2:-/tmp/pr-review-${PR}-dismissals.json}"

fail_hard() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

[[ -f "$LOG" ]] || fail_hard "dismissal log not found at $LOG (skill must write log before validator)"
jq empty "$LOG" 2>/dev/null || fail_hard "$LOG is not valid JSON"

errs=()

# Log must be from this session — stale log means the review wasn't re-run.
if mtime=$(stat -f %m "$LOG" 2>/dev/null); then :; else mtime=$(stat -c %Y "$LOG"); fi
age=$(( $(date +%s) - mtime ))
(( age < 7200 )) || errs+=("log is $((age / 60))min old (max 120min); rerun /pr-review")

sv=$(jq -r '.schema_version // 0' "$LOG")
[[ "$sv" == "1" ]] || errs+=("schema_version must be 1 (got: $sv)")

for f in pr_number agents_run bot_run bot_findings_seen \
         verified_findings dropped_findings cross_repo_refs; do
  jq -e --arg f "$f" 'has($f)' "$LOG" >/dev/null 2>&1 \
    || errs+=("missing top-level field: $f")
done

log_pr=$(jq -r '.pr_number // 0' "$LOG")
[[ "$log_pr" == "$PR" ]] || errs+=("pr_number in log ($log_pr) differs from validator arg ($PR)")

# At least one reviewer must have run (make your mandatory reviewer, e.g. security, non-optional in the skill).
agents_n=$(jq '.agents_run | length' "$LOG")
(( agents_n > 0 )) || errs+=("agents_run is empty; at least one reviewer must run")

# Every dropped finding must carry evidence, reasoning, and confidence — no silent drops.
n=$(jq '.dropped_findings | length' "$LOG")
i=0
while [[ "$i" -lt "$n" ]]; do
  for path in source severity text reasoning confidence; do
    jq -e ".dropped_findings[$i].$path" "$LOG" >/dev/null 2>&1 \
      || errs+=("dropped_findings[$i]: missing $path")
  done
  for path in command result; do
    jq -e ".dropped_findings[$i].verification.$path" "$LOG" >/dev/null 2>&1 \
      || errs+=("dropped_findings[$i]: missing verification.$path")
  done
  conf=$(jq -r ".dropped_findings[$i].confidence // \"\"" "$LOG")
  case "$conf" in low|medium|high) ;;
    *) errs+=("dropped_findings[$i]: confidence must be low|medium|high (got: $conf)") ;;
  esac
  i=$((i + 1))
done

# Every cross-repo reference in the PR must be fetched and verified, not taken on faith.
n=$(jq '.cross_repo_refs | length' "$LOG")
i=0
while [[ "$i" -lt "$n" ]]; do
  ref=$(jq -r ".cross_repo_refs[$i].ref // \"<unnamed>\"" "$LOG")
  v=$(jq -r ".cross_repo_refs[$i].verified // false" "$LOG")
  [[ "$v" == "true" ]] || errs+=("cross_repo_refs[$i] ($ref): verified must be true")
  jq -e ".cross_repo_refs[$i].evidence" "$LOG" >/dev/null 2>&1 \
    || errs+=("cross_repo_refs[$i] ($ref): missing evidence")
  jq -e ".cross_repo_refs[$i].claim" "$LOG" >/dev/null 2>&1 \
    || errs+=("cross_repo_refs[$i] ($ref): missing claim")
  i=$((i + 1))
done

# Bot accountability: every finding a bot reviewer produced must be verified or explicitly dropped.
bot_run=$(jq -r '.bot_run // false' "$LOG")
seen=$(jq -r '.bot_findings_seen // 0' "$LOG")
if [[ "$bot_run" == "true" ]] && (( seen > 0 )); then
  acc=$(jq '[.verified_findings[]?, .dropped_findings[]? | select(.source == "codex")] | length' "$LOG")
  if (( acc < seen )); then
    errs+=("bot: $seen findings observed in raw output, only $acc accounted for in verified+dropped")
  fi
fi

if (( ${#errs[@]} > 0 )); then
  printf 'Validation FAILED (%d error(s)):\n' "${#errs[@]}" >&2
  for e in "${errs[@]}"; do printf '  - %s\n' "$e" >&2; done
  exit 1
fi

printf 'OK: %s validated (PR #%s, %d verified, %d dropped, %d cross-repo)\n' \
  "$LOG" "$PR" \
  "$(jq '.verified_findings | length' "$LOG")" \
  "$(jq '.dropped_findings | length' "$LOG")" \
  "$(jq '.cross_repo_refs | length' "$LOG")" >&2
exit 0
