---
name: pr-resolver
description: Fix unresolved PR review comments, commit, re-review, and resolve threads. Use when PR has review findings that need code fixes. Usage - /pr-resolver [PR number]
user-invocable: true
allowed-tools: Agent, Bash(gh *), Bash(git *), Read, Glob, Grep, Edit, Write, AskUserQuestion
argument-hint: "[PR-number]"
---

# Resolve PR Review Comments

Fix unresolved review comments on a PR: triage each thread, apply fixes, commit, re-review, and resolve threads.

## Steps

### 1. Resolve PR number

If `$ARGUMENTS` contains a PR number, use it. Otherwise, resolve from current branch:

```bash
gh pr view --json number,headRefName -q '{number: .number, branch: .headRefName}'
```

### 2. Ensure correct branch

Verify that the current checkout matches the PR's head branch. If not, ask the user before switching.

```bash
git branch --show-current
```

If branches don't match, inform the user and ask whether to switch.

### 3-6. Triage, present, and fix

Follow the shared comment resolution procedure in `.claude/docs/comment-resolution-procedure.md` (steps 1-4). That procedure covers: fetching unresolved threads (including review bodies and conversation comments), triaging with verdicts, presenting findings, and applying fixes.

### 7. Commit and push

Stage and commit all changes with a descriptive message:

```bash
git add <specific files modified in step 6>
git commit -m "fix: address PR review comments

- Describe each fix briefly"
git push
```

Always verify with `git status` before committing. Stage only the files changed in step 6 — never use `git add -A`.

### 8. Re-review (one pass)

Re-review the updated PR using the routing table from `.claude/docs/pr-review-policy.md` — spawn the appropriate specialist agents (e.g., `devops-reviewer` for devops files, `secrets-config-reviewer` for secret configs) based on which files were modified. This catches any issues introduced by the fixes.

**Important:** This is a single re-review pass. Do not recurse — if the re-review finds new issues, present them to the user but do NOT invoke `/pr-resolver` again automatically.

### 9-10. Resolve threads and dismiss bot reviews

Follow the shared comment resolution procedure in `.claude/docs/comment-resolution-procedure.md` (steps 5-6) to resolve threads and dismiss bot reviews.

### 11. Summary

```text
## PR #{pr_number} Resolution Summary

| Category | Count |
|----------|-------|
| Fixed | X |
| Already addressed | Y |
| Not relevant | Z |
| Unclear (user decided) | W |
| Threads resolved | N |

Re-review: {X new findings / no new findings}
Bot reviews dismissed: {list or "none"}
Human re-review suggested: {list or "none"}
```

## Safety

- **One re-review pass only** — no recursive `/pr-resolver` calls
- **Don't dismiss human reviews** — only auto-dismiss bot reviews; suggest re-review for humans
- **Commit fixes separately** — don't mix resolution fixes with unrelated changes
