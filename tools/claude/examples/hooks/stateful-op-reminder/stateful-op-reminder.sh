#!/usr/bin/env bash
# PreToolUse hook — stateful operation reminder.
#
# Nudges (does not block) when detecting commands that modify external
# system state. Complements destructive-guard.sh which catches overtly
# dangerous commands. This hook catches mutations that LOOK safe but
# need the Stateful Operations Protocol (see core/operational-safety-patterns.md).
#
# Exit 0 always — reminder only, never blocks.
#
# Install: add to settings.json under hooks.PreToolUse[].hooks[]
#   before destructive-guard.sh (reminder fires first, then guard).
#
# Customize: swap the API endpoint patterns for your stack (Auth0 instead
# of Descope, Entra instead of Okta, Postgres instead of Clickhouse, etc.)

# Matching stays in-process: this runs on every Bash call, and an exec per pattern is paid on each one.
INPUT=$(</dev/stdin)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

LIB="$(dirname "$0")/../_lib"
# shellcheck source=/dev/null  # runtime-only source
[ -f "$LIB/strip-cmd.sh" ] && source "$LIB/strip-cmd.sh"
# Match the stripped form, or the reminder fires on its own trigger quoted in a -m body.
if command -v strip_cmd >/dev/null 2>&1; then
  # strip_cmd is the identity without a heredoc, quote, escape, substitution, comment or tab, so its perl is skipped then.
  case "$CMD" in
    *[\<\'\"\\\`\$#$'\t']*)
      CMD=$(strip_cmd "$CMD") ;;
  esac
fi

if [ -z "$CMD" ]; then
  exit 0
fi

NL=$'\n'

# grep -qE without the exec: on multi-line text a bare [[ =~ ]] lets . and [^…] cross lines and anchors ^ and $ to the whole text.
line_match() { # text, ERE
  local l
  case $1 in *"$NL"*) ;; *) [[ $1 =~ $2 ]]; return ;; esac
  while IFS= read -r l; do [[ $l =~ $2 ]] && return 0; done <<< "$1"
  return 1
}

# grep -qiE: nocasematch is restored before any other test reads it.
line_match_i() { # text, ERE
  local rc
  shopt -s nocasematch
  line_match "$1" "$2"; rc=$?
  shopt -u nocasematch
  return "$rc"
}

REMINDER=""

# --- Identity/auth provider management API mutations ---
# Customize: replace with your provider's management API path
if line_match_i "$CMD" '(auth0|cognito|descope|entra|okta).*(mgmt|admin|api).*(user|tenant|role|group)'; then
  REMINDER="STATEFUL OP: Identity provider user/role mutation detected. Follow the Stateful Operations Protocol: (1) Query current state of affected AND unaffected users, (2) Capture baseline, (3) Execute, (4) Verify from admin API AND end-user login perspective, (5) Spot-check unaffected users for collateral damage."
fi

# --- IAM modifications (not deletions — those are in destructive-guard) ---
if [ -z "$REMINDER" ] && line_match "$CMD" 'aws +iam +(attach|detach|put|update|create|add|remove)-'; then
  REMINDER="STATEFUL OP: IAM modification detected. Follow the Stateful Operations Protocol: (1) List current policies/roles attached, (2) Save baseline, (3) Execute, (4) Verify dependent services can still authenticate, (5) Check CloudTrail for access denials."
fi

# --- SSO/permission set changes ---
if [ -z "$REMINDER" ] && line_match "$CMD" 'aws +sso-admin +(attach|create|update|put|delete|provision)'; then
  REMINDER="STATEFUL OP: SSO permission set modification detected. Follow the Stateful Operations Protocol: (1) List current permission sets, (2) Save baseline, (3) Execute, (4) Verify affected users can still access expected accounts."
fi

# --- Database schema/data mutations ---
# Customize: add your database CLI patterns
if [ -z "$REMINDER" ] && line_match_i "$CMD" '(clickhouse|psql|mysql|mongo).*(ALTER|DROP|TRUNCATE|DELETE +FROM|INSERT +INTO)'; then
  REMINDER="STATEFUL OP: Database schema/data mutation detected. These may be IRREVERSIBLE. Follow the Stateful Operations Protocol: (1) Describe current schema, count rows, (2) Save DDL baseline, (3) Test on staging first, (4) Execute, (5) Verify schema and row counts, (6) Check consuming services for errors."
fi

# --- kubectl apply/set/replace (creating or modifying live resources) ---
if [ -z "$REMINDER" ] && line_match "$CMD" 'kubectl +(apply|set|replace|create) '; then
  REMINDER="STATEFUL OP: Kubernetes resource mutation detected. Follow the Stateful Operations Protocol: (1) Get current resource state, (2) Save baseline YAML, (3) Execute, (4) Verify rollout status and pod health, (5) Check application health endpoint."
fi

# --- Helm upgrade/install without --dry-run ---
if [ -z "$REMINDER" ] && line_match "$CMD" 'helm +(upgrade|install) ' && ! line_match "$CMD" '--dry-run'; then
  REMINDER="STATEFUL OP: Helm release mutation detected (no --dry-run). Follow the Stateful Operations Protocol: (1) Run with --dry-run first, (2) Save current release values, (3) Execute, (4) Verify rollout status, (5) Check application health."
fi

# --- Terraform apply (not plan, not destroy — destroy is in destructive-guard) ---
if [ -z "$REMINDER" ] && line_match "$CMD" 'terraform +apply' && ! line_match "$CMD" '-destroy'; then
  REMINDER="STATEFUL OP: Terraform apply detected. Follow the Stateful Operations Protocol: (1) Confirm plan output was reviewed, (2) Verify correct workspace and profile, (3) Execute, (4) Run terraform plan again (should show no changes), (5) Verify actual resources via CLI."
fi

# --- Generic curl POST/PUT/PATCH/DELETE to production APIs ---
# Note: also misses implicit POST via -d/--json (known limitation).
if [ -z "$REMINDER" ] && line_match "$CMD" 'curl [^|;&]*-X +(POST|PUT|PATCH|DELETE)' && line_match_i "$CMD" '(prod|production|api\.)'; then
  REMINDER="STATEFUL OP: HTTP mutation to a production API detected. Follow the Stateful Operations Protocol: (1) Query current state via GET first, (2) Capture baseline, (3) Execute, (4) Verify via GET, (5) Check consumer perspective."
fi

# --- Team heads-up — any detected mutation can disrupt teammates, who need a heads-up + ETA before it lands ---
if [ -n "$REMINDER" ]; then
  REMINDER="$REMINDER

TEAM HEADS-UP: This change can disrupt the team. Draft a team-chat message now and present it for the user's approval — never auto-send. The command may already be executing: announce it as in-progress, and get the draft approved before any further mutations in this change window. Template:
  :warning: *<system> change in progress* — starting ~<HH:MM local>
  *What:* <one-line description + the action being taken>
  *Impact:* <who/what is affected; expected degradation or downtime, or 'no expected impact'>
  *Window / ETA:* <start> → est. <duration>; expect normal by ~<ETA>
  *Status:* in progress — will update on completion
After the user approves, offer to post via your team-chat MCP (e.g. Slack); post only on explicit OK. Send a follow-up 'resolved / completed' message once the change is verified."
fi

# additionalContext on stdout, not stderr: the harness discards stderr on exit 0, so a reminder written there reaches no one.
if [ -n "$REMINDER" ]; then
  jq -n --arg ctx "$REMINDER" \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", additionalContext: $ctx}}'
fi

exit 0
