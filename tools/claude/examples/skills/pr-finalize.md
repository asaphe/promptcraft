---
name: pr-finalize
description: Finalize a PR before merge — clean git history, update body/ticket, verify docs. Use after code is complete and reviewed. Do NOT use for fixing review comments — use /pr-resolver instead.
user-invocable: true
allowed-tools: Bash(gh *), Bash(git *), Read, Glob, Grep, Edit, Write, AskUserQuestion
argument-hint: "[PR-number]"
---

# Finalize PR

Before starting, read `.claude/docs/pr-review-rules.md` for commit / push / review behavioral rules.

Finalize a PR by cleaning git history, updating its body and the linked ticket, and verifying docs.

This is the last step in the PR lifecycle: `/pr-review` → `/pr-resolver` → `/pr-finalize`.

## Inputs

If `$ARGUMENTS` is provided, parse it as the PR number. Otherwise, detect from the current branch:

```bash
gh pr view --json number,title,body,headRefName --jq '{number, title, body, branch: .headRefName}'
```

Extract the ticket number from the branch name (`<prefix>-XXXX-...`) or PR title / body.

## Steps

### 1. Gather current state

- Read the full diff vs main: `git diff main...HEAD --stat` then `git diff main...HEAD` for changed files
- Read the PR's current body
- Get the linked ticket details from your issue tracker (replace this step with your tracker's MCP tool or REST call)
- Check CI status — use the classification logic from `/pr-check`. If any checks are failed or action_required, flag them but continue — pr-finalize doesn't fix CI.

### 2. Clean git history

Review the commit history on the branch (`git log main..HEAD --oneline`). The PR should have a clean, professional commit history:

- **Create a backup branch first** — `git branch <branch>-backup` before any history rewriting.
- **Squash intermediate / fixup commits** — If there are commits that represent iteration (e.g., "fix approach", "switch pattern"), squash into a single logical commit. Use `git fetch origin main && git merge --ff-only origin/main && git reset --soft origin/main && git commit` for full squash. If `merge --ff-only` fails (diverging branches), STOP and use `git rebase origin/main` instead — see the squash gotcha in your global rules.
- **One logical change = one commit** — Multiple commits are fine when they represent distinct logical steps (e.g., "add migration" + "update API handler"). But "attempt 1" / "attempt 2" / "final fix" should be one commit.
- **Commit messages must be meaningful** — Each commit message should describe what and why, not the journey. Conventional commit format (`type(scope): description`).
- **Ask before force-pushing** — Show the user the before / after commit list and ask for explicit approval before running `git push --force-with-lease origin <branch>`.
- **Delete backup** after verifying the push succeeded and key files are byte-identical.

### 3. Update PR body

Rewrite the PR body to reflect the **final** state of all changes (not just the last commit). Structure:

```markdown
## Summary
- Bullet points describing what changed and why

## Changes
- File-by-file or grouped-by-area summary of modifications

## Test plan
- [x] Items that have been verified
- [ ] Items still pending

## Ticket
[<TICKET-ID>](<tracker-url>)
```

Use `gh pr edit <number> --body "..."` to update.

### 4. Update tracker ticket

Update the linked ticket via your issue tracker's API or MCP tool:

- If all CI is green and tests pass: set status to `in review`
- Append to description: a brief implementation summary and PR link

### 5. Review open PR comments

Follow the shared comment resolution procedure in `.claude/docs/comment-resolution-procedure.md` (steps 1–2 only: fetch and triage). Do NOT fix code or resolve threads — just report status:

- How many comments total
- How many are already addressed by the current diff
- How many need attention (unaddressed human comments)
- How many are bot noise (candidates for cleanup)

If unaddressed comments exist, flag them to the user and suggest `/pr-resolver` before merging.

### 6. Verify docs

Check if any new tools, APIs, config options, or behaviors were added. If so, verify the relevant docs (README, `CLAUDE.md` references, `.claude/docs/`, etc.) are updated. Report any gaps.

### 7. Report

Print a summary:

- PR number + link
- Ticket status update
- Git history: number of commits, whether squash was needed
- CI status (using pr-check classification)
- Open comments: addressed / needs attention / bot cleanup
- Any doc gaps found
