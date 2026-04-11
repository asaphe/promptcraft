# Stateful Operation Reminder

PreToolUse hook that nudges when detecting commands that modify external system state. Complements the [destructive-guard](../destructive-guard/) hook.

## Why This Exists

The destructive-guard catches overtly dangerous commands (`delete`, `destroy`, `force-push`). But production incidents are rarely caused by accidentally running `aws rds delete-db-instance`. They're caused by **plausible-looking mutations based on wrong assumptions** — a role assignment that strips permissions instead of adding them, an IAM policy change that locks out a service, a schema migration that drops a column silently.

This hook bridges the gap: it detects mutations to external systems and reminds the model to follow the Stateful Operations Protocol before proceeding.

## What It Detects

| Category | Example patterns | Reminder focus |
|----------|-----------------|----------------|
| Identity providers | Descope, Auth0, Okta, Entra, Cognito management API calls | Verify affected AND unaffected users, test login |
| AWS IAM | `aws iam attach/detach/put/update/create/remove-*` | Verify dependent services, check CloudTrail |
| AWS SSO | `aws sso-admin attach/create/update/provision` | Verify user account access |
| Databases | Clickhouse, psql, mysql, mongo with ALTER/DROP/TRUNCATE | Schema baseline, row counts, consuming services |
| Kubernetes | `kubectl apply/set/replace/create` | Rollout status, pod health, application endpoints |
| Helm | `helm upgrade/install` (without `--dry-run`) | Dry-run first, verify rollout |
| Terraform | `terraform apply` (not plan/destroy) | Plan reviewed, correct workspace, verify via CLI |
| Production APIs | `curl -X POST/PUT/PATCH/DELETE` to prod URLs | GET before and after, consumer perspective |

## Behavior

- **Exit 0 always** — never blocks, only reminds
- Reminder is emitted to stderr, which Claude Code injects into the conversation as model-facing context
- The model sees the protocol steps and is expected to follow them
- The user sees nothing unless they check stderr — this is intentional (it's a model nudge, not a user prompt)

## Installation

Place **before** `destructive-guard.sh` in the hook chain so the reminder fires first:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "/path/to/stateful-op-reminder.sh"
          },
          {
            "type": "command",
            "command": "/path/to/destructive-guard.sh"
          }
        ]
      }
    ]
  }
}
```

Requires `jq` on PATH.

## Customization

The hook is designed to be customized for your stack. Replace the identity provider, database, and API patterns:

```bash
# Replace Descope with your auth provider
if echo "$CMD" | grep -qiE 'clerk.*(user|organization|session)'; then
  REMINDER="STATEFUL OP: Clerk user/org mutation detected. ..."
fi

# Add your SaaS APIs
if echo "$CMD" | grep -qiE 'stripe.*(customer|subscription|payment)'; then
  REMINDER="STATEFUL OP: Stripe mutation detected. ..."
fi

# Add your internal services
if echo "$CMD" | grep -qiE 'curl.*internal-api\.example\.com.*(POST|PUT|DELETE)'; then
  REMINDER="STATEFUL OP: Internal API mutation detected. ..."
fi
```

## Relationship to Other Hooks

| Hook | What it catches | Behavior |
|------|----------------|----------|
| **destructive-guard** | Overtly dangerous commands (`delete`, `destroy`, `force-push`) | Blocks (hard or soft) |
| **stateful-op-reminder** | Plausible-looking mutations to external systems | Reminds (never blocks) |
| **pr-create-guard** | PR creation with missing prerequisites | Blocks on real issues, reminds otherwise |

Together, they form a layered safety net: the reminder nudges on intent, the guard blocks on action, and the PR guard verifies shared state changes.
