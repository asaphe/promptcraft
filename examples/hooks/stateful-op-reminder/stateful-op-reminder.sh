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

INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

if [ -z "$CMD" ]; then
  exit 0
fi

REMINDER=""

# --- Identity/auth provider management API mutations ---
# Customize: replace with your provider's management API path
if echo "$CMD" | grep -qiE '(descope|auth0|okta|entra|cognito).*(mgmt|admin|api).*(user|tenant|role|group)'; then
  REMINDER="STATEFUL OP: Identity provider user/role mutation detected. Follow the Stateful Operations Protocol: (1) Query current state of affected AND unaffected users, (2) Capture baseline, (3) Execute, (4) Verify from admin API AND end-user login perspective, (5) Spot-check unaffected users for collateral damage."
fi

# --- IAM modifications (not deletions — those are in destructive-guard) ---
if [ -z "$REMINDER" ] && echo "$CMD" | grep -qE 'aws +iam +(attach|detach|put|update|create|add|remove)-'; then
  REMINDER="STATEFUL OP: IAM modification detected. Follow the Stateful Operations Protocol: (1) List current policies/roles attached, (2) Save baseline, (3) Execute, (4) Verify dependent services can still authenticate, (5) Check CloudTrail for access denials."
fi

# --- SSO/permission set changes ---
if [ -z "$REMINDER" ] && echo "$CMD" | grep -qE 'aws +sso-admin +(attach|create|update|put|delete|provision)'; then
  REMINDER="STATEFUL OP: SSO permission set modification detected. Follow the Stateful Operations Protocol: (1) List current permission sets, (2) Save baseline, (3) Execute, (4) Verify affected users can still access expected accounts."
fi

# --- Database schema/data mutations ---
# Customize: add your database CLI patterns
if [ -z "$REMINDER" ] && echo "$CMD" | grep -qiE '(clickhouse|psql|mysql|mongo).*(ALTER|DROP|TRUNCATE|DELETE +FROM|INSERT +INTO)'; then
  REMINDER="STATEFUL OP: Database schema/data mutation detected. These may be IRREVERSIBLE. Follow the Stateful Operations Protocol: (1) Describe current schema, count rows, (2) Save DDL baseline, (3) Test on staging first, (4) Execute, (5) Verify schema and row counts, (6) Check consuming services for errors."
fi

# --- kubectl apply/set/replace (creating or modifying live resources) ---
if [ -z "$REMINDER" ] && echo "$CMD" | grep -qE 'kubectl +(apply|set|replace|create) '; then
  REMINDER="STATEFUL OP: Kubernetes resource mutation detected. Follow the Stateful Operations Protocol: (1) Get current resource state, (2) Save baseline YAML, (3) Execute, (4) Verify rollout status and pod health, (5) Check application health endpoint."
fi

# --- Helm upgrade/install without --dry-run ---
if [ -z "$REMINDER" ] && echo "$CMD" | grep -qE 'helm +(upgrade|install) ' && ! echo "$CMD" | grep -qE -- '--dry-run'; then
  REMINDER="STATEFUL OP: Helm release mutation detected (no --dry-run). Follow the Stateful Operations Protocol: (1) Run with --dry-run first, (2) Save current release values, (3) Execute, (4) Verify rollout status, (5) Check application health."
fi

# --- Terraform apply (not plan, not destroy — destroy is in destructive-guard) ---
if [ -z "$REMINDER" ] && echo "$CMD" | grep -qE 'terraform +apply' && ! echo "$CMD" | grep -qE -- '-destroy'; then
  REMINDER="STATEFUL OP: Terraform apply detected. Follow the Stateful Operations Protocol: (1) Confirm plan output was reviewed, (2) Verify correct workspace and profile, (3) Execute, (4) Run terraform plan again (should show no changes), (5) Verify actual resources via CLI."
fi

# --- Generic curl POST/PUT/PATCH/DELETE to production APIs ---
if [ -z "$REMINDER" ] && echo "$CMD" | grep -qE 'curl .* -X +(POST|PUT|PATCH|DELETE)' && echo "$CMD" | grep -qiE '(prod|production|api\.)'; then
  REMINDER="STATEFUL OP: HTTP mutation to a production API detected. Follow the Stateful Operations Protocol: (1) Query current state via GET first, (2) Capture baseline, (3) Execute, (4) Verify via GET, (5) Check consumer perspective."
fi

if [ -n "$REMINDER" ]; then
  echo "$REMINDER" >&2
fi

exit 0
