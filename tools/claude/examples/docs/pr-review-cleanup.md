# Bot & Review Thread Cleanup Reference

> **GitHub-specific:** uses the `gh` CLI plus GitHub's GraphQL node-type prefixes (`PRRC_`, `IC_`, `PRR_`) and `minimizeComment` / `resolveReviewThread` / `dismissPullRequestReview` mutations. Other platforms have analogous concepts but different node IDs and mutation names.

On-demand reference for PR review thread management. Pair with `pr-review-rules.md` and `comment-resolution-procedure.md`.

## Bot Comment Workflow

1. Fix or classify as false positive
2. `resolveReviewThread` (`PRRT_` node ID)
3. `minimizeComment` (classifier: `RESOLVED`)
4. Never reply to bot comments. Minimize our own replies to bots too.

## GraphQL Node Types

| Prefix | Type |
|--------|------|
| `PRRC_` | PR review comment (inline) |
| `IC_` | Issue comment (conversation) |
| `PRR_` | PR review body |

## Minimize Classifiers

`RESOLVED`, `OUTDATED`, `DUPLICATE`, `OFF_TOPIC`, `SPAM`, `ABUSE`

## Review Dismissal

- `dismissPullRequestReview` removes the badge
- `minimizeComment` on `PRR_` node collapses the body
- Both required for full cleanup after addressing CHANGES_REQUESTED

## Operational Notes

- Bots re-post on every push — re-check thread status after each push
- Use `minimizeComment` to correct wrong comments, don't reply to self-correct
- Batch GraphQL mutations — aliased mutations in a single query, not one call per thread

## Batch Mutation Example

```graphql
mutation {
  t1: resolveReviewThread(input: {threadId: "PRRT_xxx"}) { thread { isResolved } }
  t2: resolveReviewThread(input: {threadId: "PRRT_yyy"}) { thread { isResolved } }
  m1: minimizeComment(input: {subjectId: "PRRC_xxx", classifier: RESOLVED}) { minimizedComment { isMinimized } }
  d1: dismissPullRequestReview(input: {pullRequestReviewId: "PRR_xxx", message: "All changes addressed."}) { pullRequestReview { state } }
}
```
