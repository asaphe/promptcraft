# Posting PR Review Findings to GitHub

Shared reference for review agents that need to post structured findings as GitHub PR reviews.

## Prerequisites

- PR number must be known (passed as context or resolved via `gh pr view`)
- `gh` CLI authenticated (SSO may require `gh auth login` or `gh auth refresh`)

## Determine PR Context

```bash
# Get PR number for current branch
PR_NUMBER=$(gh pr view --json number -q '.number')

# Get list of changed files
gh pr diff "$PR_NUMBER" --name-only
```

## Resolve Diff Line Numbers

Before building the payload, map each finding to a specific file and line in the diff. Only lines that appear in the diff's right side (new file) can receive inline comments.

```bash
# FIRST: Save the list of changed files — this is your allowlist
CHANGED_FILES=$(gh pr diff "$PR_NUMBER" --name-only)

# View the full diff to identify valid line numbers
gh pr diff "$PR_NUMBER"

# Tip: for each finding, locate the relevant hunk and use the NEW file line number
# (the number after the + in the @@ header, or the line numbers on added/unchanged lines)
```

**CRITICAL: Before adding any comment to the payload, verify its `path` appears in `$CHANGED_FILES`.** You may read adjacent files for context, but NEVER post comments on files not in the diff. A finding on a non-diff file is either a 422 API error or a false positive — neither is acceptable.

If a finding cannot be mapped to a specific diff line (e.g., a missing file or a repo-wide consistency issue), include it in the `body` summary instead.

## Posting strategy — per-comment endpoint primary, bulk-review only for the summary

> **Important:** the `POST /pulls/{n}/reviews` endpoint with a `comments[]` array (the "bulk" path) is known to **silently drop inline comments** in some cases — comments don't appear on the PR even when the API returns 201. The reliable pattern is:
>
> 1. Post each inline finding via `POST /pulls/{n}/comments` per-comment with `commit_id`, `path`, `line`, `side: "RIGHT"`.
> 2. Then submit a final review with `gh pr review --request-changes` / `--comment` and a `--body` that summarizes counts. This sets the review state visible on the PR page; without it, the inline comments aren't grouped under a "review" event.
>
> The bulk path (`POST /reviews` with `comments[]`) is shown below for reference and remains useful for **CI contexts** where a single atomic API call is preferred and the silent-drop risk is acceptable, or for posting a summary with zero inline comments. For interactive review by an agent, prefer the per-comment path.

## Build the per-comment posts (recommended)

For each finding that maps to a diff line:

```bash
COMMIT_SHA=$(gh pr view "$PR_NUMBER" --json commits --jq '.commits[-1].oid')

gh api repos/{owner}/{repo}/pulls/$PR_NUMBER/comments \
  --method POST \
  -f commit_id="$COMMIT_SHA" \
  -f path="<file in diff>" \
  -F line=<right-side line number> \
  -f side="RIGHT" \
  -f body="**BLOCKING:** <finding text>"
```

Then submit a single review event to set the overall state:

```bash
gh pr review "$PR_NUMBER" --request-changes --body "$(cat <<'REVIEWEOF'
3 inline findings posted (1 BLOCKING, 1 ISSUE, 1 SUGGESTION). See file comments.
REVIEWEOF
)"
# or --comment for advisory-only review
```

## Bulk-review payload (alternative, with caveat above)

Write the review payload to a temp file — this avoids shell quoting issues with the `gh api` call.

**If using the bulk path:** every finding that maps to a changed file and line goes in the `comments` array. The `body` is only for a brief summary and any findings that don't map to specific diff lines.

The payload structure:

```json
{
  "event": "COMMENT | REQUEST_CHANGES",
  "body": "<summary text + findings that don't map to a diff line>",
  "comments": [
    {
      "path": "<file path in the diff>",
      "line": <line number on the RIGHT side of the diff>,
      "body": "<severity-prefixed finding text>"
    }
  ]
}
```

Concrete example with adversarial-looking entries:

```bash
cat > /tmp/pr-review-payload.json <<'ENDOFPAYLOAD'
{
  "event": "REQUEST_CHANGES",
  "body": "## Review Summary\n\n3 inline findings posted (1 BLOCKING, 1 ISSUE, 1 SUGGESTION).\n\nSee file comments for details.",
  "comments": [
    {
      "path": ".claude/skills/deploy/SKILL.md",
      "line": 3,
      "body": "**BLOCKING:** Unknown frontmatter field `skill_name`. Did you mean `name`?"
    },
    {
      "path": ".claude/skills/deploy/SKILL.md",
      "line": 5,
      "body": "**BLOCKING:** `allowed-tools` must be a comma-separated string (`Bash(gh *), Read`), not a YAML list."
    },
    {
      "path": ".claude/agents/my-agent.md",
      "line": 7,
      "body": "**ISSUE:** Missing error handling — step exits 0 on failure, masking real problems."
    },
    {
      "path": ".claude/agents/my-agent.md",
      "line": 15,
      "body": "**SUGGESTION:** Bare `Bash` without scope pattern — project convention is to always scope (e.g., `Bash(gh *)`)."
    }
  ]
}
ENDOFPAYLOAD
```

### Field Reference

| Field | Required | Description |
|-------|----------|-------------|
| `event` | Yes | `COMMENT` (advisory) or `REQUEST_CHANGES` (blocking findings exist) |
| `body` | Yes | Brief summary + any findings that don't map to a diff line |
| `comments` | Yes* | Array of inline comments on specific files/lines (*omit only if zero findings map to diff lines) |
| `comments[].path` | Yes | File path relative to repo root — must appear in `gh pr diff --name-only` |
| `comments[].line` | Yes | Line number in the **right side** of the diff (new file). Must exist in a diff hunk. |
| `comments[].body` | Yes | Finding text in markdown — prefix with severity (`**BLOCKING:**`, `**ISSUE:**`, `**SUGGESTION:**`) |

### Event Selection

- Use `COMMENT` when all findings are SUGGESTIONS or ISSUES (no BLOCKING)
- Use `REQUEST_CHANGES` when any finding is BLOCKING

## Post the Review

```bash
gh api repos/{owner}/{repo}/pulls/$PR_NUMBER/reviews --input /tmp/pr-review-payload.json
```

The `{owner}/{repo}` can be resolved automatically by `gh`:

```bash
gh api "repos/$(gh repo view --json nameWithOwner -q '.nameWithOwner')/pulls/$PR_NUMBER/reviews" \
  --input /tmp/pr-review-payload.json
```

## Clean Up

```bash
rm -f /tmp/pr-review-payload.json
```

## Troubleshooting

| Error | Cause | Fix |
|-------|-------|-----|
| 422 "Validation Failed" with `pull_request_review_thread.line` | The `line` number doesn't exist in the diff hunk | Use only line numbers visible in the diff's right side. Remove the offending comment or adjust the line number. |
| 422 "Validation Failed" with `pull_request_review_thread.path` | The `path` doesn't match a file in the diff | Verify file path against `gh pr diff --name-only` output |
| 401 "Bad credentials" | Token expired or lacks `repo` scope | Run `gh auth refresh` or `gh auth login` |
| Empty comments array with inline findings | JSON encoding issue | Ensure the temp file is valid JSON — use `jq . /tmp/pr-review-payload.json` to validate before posting |

## CI Context (MCP inline comments + gh pr review)

When running inside `claude-code-action` (CI), inline comments are posted via the `mcp__github_inline_comment__create_inline_comment` MCP tool one at a time. This tool does **not** set a review event type — all comments land as individual `COMMENTED` reviews with empty bodies. To set REQUEST_CHANGES or post a summary body, submit a final review after all inline comments:

**Important:** Always use a heredoc with a quoted delimiter (`<<'REVIEWEOF'`) for `--body` to prevent backticks from being interpreted as command substitution.

```bash
PR=$(gh pr view --json number -q .number)

gh pr review "$PR" --request-changes --body "$(cat <<'REVIEWEOF'
Requesting changes — blocking issues found: <one-line summary per BLOCKING finding>
REVIEWEOF
)"

gh pr review "$PR" --comment --body "$(cat <<'REVIEWEOF'
Review complete: N findings (X BLOCKING, Y ISSUE, Z SUGGESTION). No blocking issues.
REVIEWEOF
)"
```

This is a separate API call from the inline comments — it sets the review state visible on the PR page and in the sidebar. Without it, the PR shows no reviewer decision even when BLOCKING issues were posted.

## Integration Notes

- **Inline comments are the primary output.** Every finding that can be pinned to a file+line in the diff MUST be an inline comment in `comments[]`, not text in `body`. Reviewers should see findings directly on the lines they affect in the Files Changed tab.
- The `body` field is for a brief summary (finding counts, overall assessment) and any findings that genuinely cannot map to a diff line (e.g., missing file, cross-repo consistency).
- If the PR number is not available (e.g., agent invoked outside PR context), output the structured markdown review to stdout instead — this is the fallback behavior.
- Always clean up the temp file after posting, even if the API call fails.
