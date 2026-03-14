# Git Safety Rules

- **Don't push to branches after their PR is merged** — Once a PR is merged, its branch is done. If follow-up work is needed (state moves, fixes), create a new branch from `main`. Pushing commits to a merged branch creates orphans and confusion.

- **In worktrees and parallel sessions, verify git branch before every commit** — When working in a worktree (`/tmp/wt-*` or non-standard path) or when parallel Claude sessions may be running, always run `git branch --show-current` immediately before `git commit`. A commit to the wrong branch in a parallel session creates orphaned commits and requires cherry-pick + hard reset to fix.

- **Confirm the exact worktree path before writing files** — When a worktree is at `/tmp/wt-XXXX`, run `git worktree list` to get the canonical path before any Write or Edit operation. Never derive the path from the ticket number — the worktree setup may use a different numbering. A mismatch means changes are written to the wrong directory.

- **Always run `git add` and `git commit` from the repo root** — After running commands that may change `$PWD` (e.g., `poetry run`, `pnpm`, `terraform`, `cd` into a module), verify `pwd` is the repo root before staging files. Use absolute paths or `git -C /path/to/repo add <file>` when in a subdirectory.

- **After "I merged" or "just merged", re-read git state before proceeding** — When the user mentions they merged a PR or branch, first clarify which branch was merged into which if ambiguous (e.g., "Just merged feature-X into main?"). Then immediately run `git fetch && git log --oneline -5` on the relevant branch to ground the session state. Do not rely on pre-merge context. Re-read the target module/file before taking action.

- **Never force-push without explicit user approval** — Force-push rewrites remote history and can permanently destroy work that others have pushed or that exists only on the remote. Always stop and ask before running any force-push form (`git push --force`, `git push -f`, `git push --force-with-lease`, or `git push origin +<branch>`). Even in worktrees or "solo" branches, ask first. When force-pushing is approved, record the before-state (`git log --oneline origin/<branch>`) and after-state (`git log --oneline origin/<branch>` run again post-push) and report both so the outcome can be verified. A force-push without a before/after comparison cannot be audited.

- **Fixup vs squash — know the difference** — `git rebase -i` with `fixup` discards the fixup commit's message (keeps only the target commit's message). `squash` combines both messages. When the user says "fixup", use fixup — they want a clean single message, not a combined one.

- **Never create empty placeholder files** — Only create files when they have actual content to write. Empty files add clutter and serve no purpose. If a file will be populated later, wait until the content is ready.
