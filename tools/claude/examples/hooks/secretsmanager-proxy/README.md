# Secretsmanager Proxy

A **PreToolUse** hook that auto-wraps secret-fetching commands with a token-optimization proxy bypass.

## Why

Token-optimization tools (like [RTK](https://github.com/rtk-ai/rtk)) filter and summarize CLI output to reduce token usage. This is great for `git status` or `kubectl get pods`, but destructive for commands that return JSON secret values — the filtering truncates the JSON, making it unusable.

This hook detects commands that fetch secrets and automatically wraps them with the proxy bypass command, ensuring full JSON output.

## Behavior

| Command | Action |
|---------|--------|
| `aws secretsmanager get-secret-value --secret-id ...` | Rewrite to `rtk proxy aws secretsmanager get-secret-value ...` |
| `aws secretsmanager batch-get-secret-value ...` | Rewrite to `rtk proxy aws secretsmanager batch-get-secret-value ...` |
| Already has `rtk proxy` prefix | Allow (no double-wrap) |
| All other commands | Allow |

## Setup

1. Edit the script: change `PROXY_CMD` and command patterns to match your setup
2. Register as a PreToolUse hook on `Bash`:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "/path/to/secretsmanager-proxy.sh"
          }
        ]
      }
    ]
  }
}
```

## Customization

**Different proxy command:** Change `PROXY_CMD="rtk proxy"` to your bypass command.

**Additional patterns:** Add more `grep -qE` patterns for other commands that need full output:

```bash
# Terraform plan output
if echo "$CMD" | grep -qE 'terraform plan'; then ...

# API responses
if echo "$CMD" | grep -qE 'curl.*api\..*/secrets'; then ...
```

## Hook Ordering

If you use a token-rewriting hook (like RTK's rewrite hook), register this hook **after** it. The rewrite hook may change `aws` to `rtk aws`, and this hook needs to catch both forms.
