---
name: pr-review
description: Review a PR and post inline findings. Routes to specialized reviewers by file type. Usage - /pr-review [PR number]
user-invocable: true
allowed-tools: Agent, Bash(gh *), Bash(jq *), Bash(rm *), Read, Glob, Grep, Write, AskUserQuestion
argument-hint: "[PR-number]"
---

# Review PR

Review a PR by routing changed files to specialized reviewer agents, collecting findings, and posting them as inline GitHub comments after user approval.

## Steps

### 1. Resolve PR number

If `$ARGUMENTS` contains a PR number, use it. Otherwise, resolve from current branch:

```bash
gh pr view --json number -q '.number'
```

If that fails, list open PRs by the current user and ask which to review.

### 2. Read review methodology

Read `.claude/docs/pr-review-rules.md` before proceeding — it contains finding verification, severity classification, tone guidelines, and common pitfalls that apply to ALL reviewers.

### 3. Fetch changed files

```bash
gh pr diff $PR_NUMBER --repo <org>/<repo> --name-only
```

### 4. Route by file scope

Use the routing table from `.claude/docs/pr-review-policy.md` to classify files and spawn the appropriate reviewer agents **in parallel**.

If no files match any category, inform the user and stop.

### 5. Agent prompt template

Each reviewer agent receives this prompt structure:

```text
You are reviewing PR #{pr_number} in <org>/<repo>.

IMPORTANT: Read `.claude/docs/pr-review-rules.md` first — it contains the review methodology you MUST follow.

Your file scope (ONLY review these files):
{file_list}

Instructions:
1. Fetch the full diff for your files: `gh pr diff {pr_number} --repo <org>/<repo>`
2. For each file, read the full file content for context
3. Check against project conventions (read CLAUDE.md and relevant subdirectory CLAUDE.md files)
4. Verify every finding against the codebase — check sibling files for the same pattern before flagging
5. Do NOT post anything to GitHub — return findings to me

Return findings as a structured list. For each finding:
- file: relative path
- line: line number in the NEW file (right side of diff)
- severity: BLOCKING, ISSUE, or SUGGESTION
- body: markdown description of the issue

If you find no issues, return "No findings."
Don't assume — check the codebase and verify every finding before reporting it.
```

For application code, spawn the `general-reviewer` agent instructed to:

- Read the project `CLAUDE.md` and language-specific subdirectory `CLAUDE.md` files
- Check code standards (typing, imports, patterns, naming conventions)
- Look for security issues (OWASP top 10, injection, auth bypass)
- Verify test coverage for new functionality

### 6. Collect and deduplicate findings

Gather results from all agents. Deduplicate findings on the same file+line. Merge severity upward (SUGGESTION < ISSUE < BLOCKING — if one agent says SUGGESTION and another says ISSUE for the same finding, use ISSUE).

### 7. Present findings to user

Display a table of all findings grouped by file:

```text
## PR #{pr_number} Review Findings

### path/to/file.py
| Line | Severity | Finding |
|------|----------|---------|
| 42   | BLOCKING | Description... |
| 65   | ISSUE | Description... |
| 78   | SUGGESTION | Description... |

### path/to/other.tf
| Line | Severity | Finding |
|------|----------|---------|
| 15   | SUGGESTION | Description... |

**Summary:** X BLOCKING, Y ISSUE, Z SUGGESTION across N files
```

Ask the user: "Post these findings to the PR? You can remove or edit items first."

If the user wants to edit, apply their changes. If they say no, stop.

### 8. Build and post review payload

Follow `.claude/docs/pr-review-posting.md` exactly:

1. Get the latest commit SHA:

   ```bash
   gh pr view $PR_NUMBER --repo <org>/<repo> --json commits --jq '.commits[-1].oid'
   ```

1. Build the JSON payload:
   - Every finding that maps to a file+line in the diff goes in `comments[]`
   - Findings that can't map to a diff line go in `body`
   - `event` = `REQUEST_CHANGES` if any BLOCKING findings, else `COMMENT` (ISSUE findings use COMMENT, not REQUEST_CHANGES)
   - `body` = brief summary with finding counts

1. Validate the payload:

   ```bash
   jq . /tmp/pr-review-payload.json
   ```

1. Post:

   ```bash
   gh api repos/<org>/<repo>/pulls/$PR_NUMBER/reviews --input /tmp/pr-review-payload.json
   ```

1. Clean up:

   ```bash
   rm -f /tmp/pr-review-payload.json
   ```

### 9. Sweep existing comments and reviews

After posting (or if the user declines posting), sweep all pre-existing feedback on the PR:

1. **Review threads** — fetch via GraphQL `reviewThreads`. Resolve any that are addressed by the current code or are no longer relevant.
2. **Review bodies** — fetch via `gh api repos/.../pulls/{n}/reviews`. For bot reviews (`github-actions[bot]`, `chatgpt-codex-connector[bot]`, `cursor[bot]`):
   - If `state` is `CHANGES_REQUESTED` or `APPROVED`: dismiss with `gh api .../reviews/{id}/dismissals -X PUT -f message="Addressed"`
   - For any bot review (including `COMMENTED` which can't be dismissed): minimize with GraphQL `minimizeComment` mutation using the review's node ID and classifier `RESOLVED` (or `OUTDATED`/`OFF_TOPIC` as appropriate). This hides the review body behind a "This comment was marked as resolved" fold. Do NOT blank review bodies — that erases context.
   - To get node IDs: `gh api graphql -f query='{ repository(...) { pullRequest(number: N) { reviews(first: 20) { nodes { id author { login } state } } } } }'`
   - To minimize: `gh api graphql -f query='mutation { minimizeComment(input: { subjectId: "NODE_ID", classifier: RESOLVED }) { minimizedComment { isMinimized } } }'`
3. **Conversation comments** — fetch via `gh api repos/.../issues/{n}/comments`. Flag any unresolved ones to the user.
4. **PR body** — read the description for checklists or inline questions that need attention.

### 10. Summary

```text
Posted review on PR #{pr_number}: X BLOCKING, Y ISSUE, Z SUGGESTION across N files.
Event: REQUEST_CHANGES / COMMENT
Pre-existing threads resolved: N
Bot reviews dismissed/blanked: N
```

## Safety

- **Verify every finding** — agents produce false positives; cross-check against codebase patterns
- **Only comment on diff lines** — line numbers must exist in the diff's right side
- **Clean up temp files** — always remove `/tmp/pr-review-payload.json` after posting
