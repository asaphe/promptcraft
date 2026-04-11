# PR Create Guard

PreToolUse hook that verifies pre-creation conditions before allowing `gh pr create`. Blocks on real problems, emits a verification checklist on pass.

## What It Checks

### Hard Blocks (exit 2 — command blocked)

| Check | Why |
|-------|-----|
| Zero diff vs `origin/main` | PR would be empty — all changes already on main |
| Branch not pushed to remote | PR would reference commits that don't exist on GitHub |
| Local HEAD differs from remote | Unpushed commits won't appear in the PR |
| Uncommitted changes | Files the user expects in the PR won't be there |

### Verification Checklist (exit 0 — model-facing reminder)

When all hard checks pass, the hook emits a checklist to stderr:

```
PR PRE-CREATION VERIFICATION — 5 files, 3 commits, +120/-30 lines:
  [ ] Diff reviewed — changes match what was intended (no accidental inclusions)
  [ ] PR body accurately describes the FINAL state of changes
  [ ] Base branch is correct (should be main unless targeting a release branch)
  [ ] Linked ticket/issue updated
  [ ] Tests pass locally (or explicitly noted as untestable)
```

The model sees this and is expected to verify each item before proceeding. The user sees nothing unless they check stderr — this is a model nudge, not a user prompt.

## Installation

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "/path/to/pr-create-guard.sh"
          }
        ]
      }
    ]
  }
}
```

The script early-exits (before any git operations) if the command isn't `gh pr create`, so the overhead on non-PR commands is minimal (jq + grep).

Requires `jq` and `git` on PATH.

## Relationship to destructive-guard

The `destructive-guard` hook also soft-blocks `gh pr create` with a generic "confirm with user" message. The two hooks are complementary:

1. **pr-create-guard** runs first — blocks on hard prerequisites, emits verification checklist
2. **destructive-guard** runs second — if pr-create-guard passes, destructive-guard's soft block gives the user a final confirmation prompt

This means PRs go through two layers: technical verification (pr-create-guard) and human confirmation (destructive-guard).

## Why Not Just Use destructive-guard?

The destructive-guard's PR check is a generic "are you sure?" prompt. It doesn't verify anything about the actual state of the branch. The pr-create-guard catches real problems:

- PRs created from stale branches (already merged but not deleted)
- PRs missing commits that the user assumes are pushed
- PRs that accidentally exclude uncommitted work
- PRs where the model skips reviewing the actual diff
