---
name: pr-check
description: Check CI statuses and review comments across PRs. Resolves addressed/irrelevant comments, asks about unclear ones. Use for CI monitoring and comment triage. Do NOT use when you need to fix code and re-review — use /pr-resolver instead. Usage - /pr-check [PR numbers...]
user-invocable: true
allowed-tools: Bash(gh *), Bash(cd *), Bash(cat *), Bash(rm *), Read, Glob, Grep, Edit, Write, AskUserQuestion
argument-hint: "[PR-numbers]"
---

# Check PRs

Before starting, read `.claude/docs/pr-review-rules.md` for review behavioral rules.

Full health check for one or more PRs: CI statuses + review comments.

## Steps

### 1. Determine which PRs to check

If `$ARGUMENTS` is provided, parse it as space- or comma-separated PR numbers. If no argument is given but there is a PR in the current session context (e.g., a branch or PR number discussed in the conversation), use that PR. Only fall back to discovering all open PRs by the current user when there is no session context:

```bash
gh pr list --author @me --state open --json number,title,headRefName --jq '.[] | "\(.number) \(.title) [\(.headRefName)]"'
```

Ask the user to confirm which PRs to check if more than 5 are found.

## Part A: CI Status

### 2. Check each PR

For each PR, use the GitHub API to get accurate check status. Do NOT use `gh pr checks` — it renders `cancelled` as `fail`.

```bash
gh pr view {pr_number} --json statusCheckRollup,title,number,headRefName --jq '{
  number: .number,
  title: .title,
  branch: .headRefName,
  checks: [.statusCheckRollup[] | {name: .name, status: .status, conclusion: .conclusion}]
}'
```

### 3. Classify results

For each PR, classify every check into one of:

- **passed** — `conclusion == "success"` or `conclusion == "skipped"` or `conclusion == "neutral"`
- **failed** — `conclusion == "failure"` or `conclusion == "timed_out"`
- **cancelled** — `conclusion == "cancelled"` (NOT a real failure — usually concurrency conflicts)
- **pending** — `status == "queued"` or `status == "in_progress"` or `status == "waiting"` or `status == "pending"`
- **expected** — `status == "expected"` (check was never reported — likely a branch ruleset mismatch)
- **action_required** — `conclusion == "action_required"` or `conclusion == "stale"` or `conclusion == "startup_failure"` (uncommon — surface explicitly)

### 4. Present CI summary

```text
PR #1234 — "Fix the thing" [branch-name]
  [PASS] 12 passed  [PEND] 2 pending  [FAIL] 0 failed  [CANCEL] 1 cancelled  [EXPECTED] 0 expected  [ACTION] 0 action required
```

Only show detail sections for non-passed checks. If all checks pass, show a single pass line.

### 5. Offer CI actions

If there are failed or cancelled checks, resolve workflow run IDs from the branch:

```bash
gh run list --branch {branch} --limit 20 \
  --json databaseId,workflowName,conclusion \
  --jq '.[] | select(.conclusion == "failure" or .conclusion == "cancelled") | "\(.databaseId)\t\(.workflowName)\t\(.conclusion)"'
```

Then offer:

1. **Re-run failed** — `gh run rerun {run_id} --failed`
2. **Re-run cancelled** — `gh run rerun {run_id}` (no `--failed` flag — cancelled runs haven't failed)
3. **Delete failed runs** — `gh run delete {run_id}`

If there are "expected" checks, flag that the branch ruleset may need updating.

## Part B: Review Comments

Follow the shared procedure in `.claude/docs/comment-resolution-procedure.md` (steps 1–7). That procedure covers: fetching unresolved threads, triaging with verdicts, presenting findings, applying fixes, resolving threads, minimizing addressed review body comments, and dismissing bot reviews.

After applying fixes, commit and push changes before resolving threads.

## Summary

Present a final combined summary:

```text
PR #1234 — "Fix the thing" [branch-name]
  CI:       [PASS] 12 passed (all green)
  Comments: 4 resolved (2 fixed, 1 already addressed, 1 not relevant)
```

## Safety

- Commit and push fixes before resolving threads
- After all comments are resolved and CI is green, use `/pr-finalize` to clean git history, update PR body, and verify docs before merge
