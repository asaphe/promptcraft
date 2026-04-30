# post-push-hygiene

PostToolUse hook that fires after a successful `git push` and emits a checklist nudging the model to resolve review threads, update the PR body, and update the issue tracker.

## Why this exists

After a push, three things commonly slip:

1. Review threads addressed in the new commits aren't resolved on the PR
2. The PR body still describes an earlier scope (the diff drifted as work progressed)
3. The issue tracker / ticket status hasn't been updated

The model has no automatic prompt to do these — they have to be remembered. This hook injects a short checklist into the next turn as `additionalContext`, raising them naturally without a hard block.

## What it does

1. Triggered by any successful `git push` (flag-permissive: `git -C dir push`, `git --no-pager push`, etc.)
2. Skips if the push output contains failure markers (`rejected`, `error`, `fatal`, `failed`)
3. Invalidates a repo+branch-scoped PR cache (if you maintain one) so subsequent reads fetch fresh PR state
4. If `.tf` files are in the diff vs `origin/main`, adds a Terraform-specific line about apply timing
5. Emits the checklist as `additionalContext`

## Configuration

```jsonc
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": "/absolute/path/to/post-push-hygiene.sh" }
        ]
      }
    ]
  }
}
```

## Customization

The checklist lines are hardcoded for simplicity. To add or remove items, edit `CHECKLIST` in the script. Common additions:

- "Run E2E test on staging deployment after the merge"
- "Notify the on-call channel if the change touches alerting"
- "Confirm CI passed before requesting review"
