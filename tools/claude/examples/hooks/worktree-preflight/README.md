# worktree-preflight

Hard-blocks `git` write operations against a guarded repo root that's on a non-main branch.

## Why this exists

When you have a convention "repo roots stay on `main`, branch work happens in worktrees under `/tmp/`", the failure mode is: another session left the root on a feature branch, and the next session walks in, runs `git commit` from the root, and pollutes the other session's work tree. The model can't see the other session's intent — only that the branch isn't main.

This hook closes that gap: any `git` mutation directed at a guarded repo's root (not a worktree, not a subdirectory) is hard-blocked when the branch is anything other than `main` / `master`.

## What it gates

**Block:** `git commit`, `git push`, `git merge`, `git rebase`, `git reset`, `git cherry-pick`, `git revert`, `git pull`, `git am`, `git apply`, `git stash push/save`, `git tag`, `git branch -D/-d/-m`, `git add`, `git rm`, `git mv`.

**Pass:** read-only ops (`git log`, `git status`, `git diff`, `git show`), worktrees (`/tmp/...`), repos outside `WORKTREE_GUARD_ROOT`, the root when it's on `main`/`master`, subdirectories of guarded repos (only roots are protected).

The flag-permissive pattern catches `git -C dir commit`, `cd /tmp/wt && git commit`, etc.

## Configuration

```bash
export WORKTREE_GUARD_ROOT="$HOME/repos"  # default; point to your monorepo parent
```

Then in `.claude/settings.json`:

```jsonc
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": "/absolute/path/to/worktree-preflight.sh" }
        ]
      }
    ]
  }
}
```

Sources `../_lib/strip-cmd.sh` (required) and `../_lib/hook-diag.sh` (optional).

## Exit codes

| Exit | Meaning |
|------|---------|
| 0 | Allow (read-op, worktree, unguarded repo, or root on main) |
| 2 | Hard block — root is on non-main branch with a write op |

## Recovery message

The block message prints three commands the user can run to either confirm the root is theirs or unblock the session:

```text
git -C <repo> status                   # confirm clean / no other session active
git -C <repo> checkout main            # restore root state
git worktree add /tmp/<name> -b <branch> main   # do branch work in a worktree
```
