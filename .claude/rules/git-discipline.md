# Git Discipline

## Safety
- **Create a new branch from `main` for follow-up work** — Don't push to merged branches.

- **Never force-push without approval** — Always ask first.

- **Create files only with actual content** — No empty placeholders.

## Cross-Repo Operations
- **Fetch before asserting what's on main** — Before claiming "main has X" or "main doesn't have X", run `git fetch origin main` and check `origin/main`, not the local `main` ref.

- **Never stack commits for separate PRs on one branch** — If two changes need separate PRs, create separate branches from `origin/main` from the start.

## PR Creation
- **Run test plan items before opening the PR** — Execute every verifiable checkbox and check it off before creating the PR.

- **Scan every diff for PII before committing** — This is a public repository. Every commit is permanent and indexed.
