# AWS Auth Check

A **UserPromptSubmit** hook that validates AWS SSO sessions at session start and injects auth status into the conversation context.

## Why

Without this hook, every AWS command needs `export AWS_PROFILE=X &&` prepended — adding boilerplate to every Bash call. In a data-mined analysis of 716 sessions, this accounted for ~6,700 redundant tool calls (35% of all AWS usage).

This hook solves two problems:

1. **Eliminates boilerplate** — The agent knows which profiles are active and can use them directly
2. **Detects expired sessions early** — Instead of failing on the 5th AWS command, the agent knows at session start and can prompt the user to re-authenticate

## Behavior

On each user message, the hook:

1. Checks cache (5-minute TTL) to avoid re-checking on every turn
2. If cache is stale, validates each AWS profile via `sts get-caller-identity`
3. Injects a context line like: `AWS SSO: prod=valid, dev=expired. Use AWS_PROFILE=prod (active).`

The agent sees this context and can:

- Skip `export AWS_PROFILE=prod &&` boilerplate
- Proactively suggest `! aws sso login --profile dev` when dev is expired
- Know which profile to use without asking

## Setup

Register as a UserPromptSubmit hook in `~/.claude/settings.json`:

```json
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "/path/to/aws-auth-check.sh"
          }
        ]
      }
    ]
  }
}
```

## Customization

**Add/remove profiles:** Edit the `check_profile` calls in the script. Each profile adds ~1s to the check (only when cache is stale).

**Adjust cache TTL:** Change `CACHE_TTL=300` (default: 5 minutes). SSO tokens typically last 8-12 hours, so even 30 minutes is safe.

**Linux compatibility:** Replace `stat -f %m` with `stat -c %Y` for GNU stat.

## Performance

- **Cached:** < 5ms (reads temp file)
- **Uncached:** ~2s per profile (network call to STS)
- **Token cost:** ~50 tokens per turn (injected context string)

The 5-minute cache means the STS check runs at most once per 5 minutes, not on every user message.
