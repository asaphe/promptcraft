# Review Verification Guard

A **PreToolUse** hook that blocks PR review and comment posting with an operation-specific verification checklist.

## Why

The biggest risk in agent-driven PR reviews is **false findings**. A wrong finding destroys reviewer credibility faster than a missing finding costs quality. Once reviewers (human or agent) lose credibility, their future findings get ignored — even correct ones.

The most common failure modes:

| Failure | Cause |
|---------|-------|
| Finding contradicts actual code | Agent read the diff patch, not the final file on HEAD |
| Duplicate finding | Agent didn't check existing comments before posting |
| Stale reference | Agent verified against an intermediate commit, not the final one |
| Speculative claim | Agent asserted a resource exists/doesn't exist without checking live state |

This hook forces a pause before every review/comment post, surfacing a checklist tailored to the specific operation type.

## Behavior

The hook intercepts `gh api` and `gh pr comment` commands that **write** to PRs:

| Command Pattern | Action |
|----------------|--------|
| `gh api repos/.../pulls/N/reviews` (POST) | Block with full review checklist |
| `gh pr comment` | Block with evidence checklist |
| `gh api repos/.../pulls/N/comments` (POST) | Block with inline comment checklist |
| `gh api repos/.../pulls/comments/N -X PATCH` | Block with lighter update check |
| Read operations (GET, DELETE) | Allow |

**Soft block** — uses JSON `permissionDecision: "block"` with exit 0. If you have `Bash(*)` in your allow list, this gets overridden. For hard enforcement, change to `exit 2` with the reason on stderr.

## Setup

Register as a PreToolUse hook on `Bash` in `~/.claude/settings.json`:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "/path/to/review-verification-guard.sh"
          }
        ]
      }
    ]
  }
}
```

## Customization

### Adjust the Checklist

Edit the `REASON` strings in the script to match your review standards. Common additions:

- `[ ] Ran the test suite locally to verify the finding`
- `[ ] Checked if the issue exists on main (may be a pre-existing problem)`
- `[ ] Security findings verified against OWASP reference`

### Hard Block vs Soft Block

The default is a soft block (JSON + exit 0). To make it a hard block that `Bash(*)` cannot override:

```bash
if [ -n "$REASON" ]; then
  echo "$REASON" >&2
  exit 2
fi
```

### Scope Narrowing

To only guard reviews on specific repos, add a repo filter:

```bash
REPO=$(echo "$CMD" | grep -oE 'repos/[^/]+/[^/]+' | head -1)
if [ "$REPO" != "repos/your-org/your-repo" ]; then
  exit 0
fi
```
