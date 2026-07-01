#!/usr/bin/env bash
# PreToolUse:Bash — gates PR review submission on a valid dismissal log. WARN by default; BLOCK on security-sensitive PRs. See README.md.

INPUT=$(cat)
CMD=$(printf '%s\n' "$INPUT" | jq -r '.tool_input.command // empty')

[[ -n "$CMD" ]] || exit 0

DIR="$(cd "$(dirname "$0")" && pwd)"
VALIDATOR="${DIR}/validate-pr-review.sh"

PR=""
# New review-comment POSTs to /pulls/{n}/comments, but NOT thread-reply posts (.../comments/{id}/replies) which are ad-hoc follow-ups.
if printf '%s\n' "$CMD" | grep -qE 'gh api[[:space:]]+.*[/]pulls[/][0-9]+[/]comments(/[0-9]+/replies)?' \
   && ! printf '%s\n' "$CMD" | grep -qE '[/]pulls[/][0-9]+[/]comments[/][0-9]+[/]replies'; then
  PR=$(printf '%s\n' "$CMD" | grep -oE '/pulls/[0-9]+' | grep -oE '[0-9]+' | head -1)
elif printf '%s\n' "$CMD" | grep -qE 'gh pr review.*(--request-changes|--comment)'; then
  PR=$(printf '%s\n' "$CMD" | grep -oE 'gh pr review[[:space:]]+[0-9]+' | grep -oE '[0-9]+' | head -1)
  if [[ -z "$PR" ]]; then
    PR=$(gh pr view --json number -q '.number' 2>/dev/null || true)
  fi
fi

[[ -n "$PR" ]] || exit 0

LOG="/tmp/pr-review-${PR}-dismissals.json"

# Narrow, filename-based patterns for security-sensitive changes — intentionally conservative to avoid false-positive blocks.
SECURITY_REGEX='(iam[^/]*\.tf$|.*_iam\.tf$|.*oidc.*|.*secret[^/]*\.tf$|secrets/.*\.ya?ml$|.*ssm.*\.tf$|.*kms.*\.tf$|.*rbac.*\.ya?ml$|.*serviceaccount.*\.ya?ml$|.*_policy\.json$|policy\.json$)'

SECURITY_FILES=""
if command -v gh >/dev/null 2>&1; then
  # 2s timeout — if gh is slow/offline, fall back to WARN-only behavior.
  SECURITY_FILES=$(timeout 2 gh pr diff "$PR" --name-only 2>/dev/null | grep -iE "$SECURITY_REGEX" || true)
fi

IS_SECURITY_PR=0
[[ -n "$SECURITY_FILES" ]] && IS_SECURITY_PR=1

LOG_VALID=0
if [[ -f "$LOG" ]]; then
  if bash "$VALIDATOR" "$PR" >/dev/null 2>&1; then
    LOG_VALID=1
  fi
fi

# BLOCK: security-sensitive PR with no valid dismissal log.
if [[ "$IS_SECURITY_PR" -eq 1 && "$LOG_VALID" -eq 0 ]]; then
  cat >&2 <<EOF
BLOCK: posting review on PR #${PR} without a valid /pr-review dismissal log.

This PR touches security-sensitive paths:
$(printf '%s\n' "$SECURITY_FILES" | sed 's/^/  - /')

Ad-hoc reviews on IAM/OIDC/secrets/SSM/KMS/RBAC PRs have a track record of
producing rose-tinted verdicts. Dispatch the specialist reviewers via
/pr-review so each axis (trust principals, secret ARNs, SSM paths, environment
scope, role naming, blast radius) gets per-axis positive evidence.

What to do:
  1. Run /pr-review ${PR}
  2. Address any verified findings
  3. Re-attempt posting — the dismissal log at ${LOG} will satisfy this gate.

To override (rare — only when the security paths are genuinely out-of-scope for
the review you're posting): write ${LOG} with
'{"override": "out-of-scope security paths", "reason": "<why>"}' AND state the
same reasoning in the review body.
EOF
  exit 2
fi

# WARN: missing or invalid log on a non-security PR — informational, not blocking.
WARN=""
if [[ ! -f "$LOG" ]]; then
  WARN="WARN: posting review on PR #${PR} without a /pr-review dismissal log at ${LOG}. If you ran /pr-review, the skill should have written it. Manual ad-hoc comments don't require a log."
elif [[ "$LOG_VALID" -eq 0 ]]; then
  out=$(bash "$VALIDATOR" "$PR" 2>&1)
  WARN="WARN: dismissal log for PR #${PR} fails validation. Output:
${out}
This is WARN-only — submission allowed. Fix the log and rerun /pr-review for the next push."
fi

if [[ -n "$WARN" ]]; then
  jq -n --arg ctx "$WARN" '{
    "hookSpecificOutput": {
      "hookEventName": "PreToolUse",
      "additionalContext": $ctx
    }
  }'
fi

exit 0
