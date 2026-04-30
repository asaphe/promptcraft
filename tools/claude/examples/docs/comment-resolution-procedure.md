# Comment Resolution Procedure

> **GitHub-specific:** uses the `gh` CLI and GitHub's GraphQL `reviewThreads` / `resolveReviewThread` / `minimizeComment` / `dismissPullRequestReview` mutations. Adapt for GitLab / Bitbucket / Gerrit by mapping each step to their thread-resolution APIs (note that some platforms don't expose a programmatic equivalent of GitHub's `minimizeComment`).

Shared procedure for triaging and resolving PR review comments. Referenced by `/pr-check`, `/pr-resolver`, and `/pr-finalize`.

## 1. Fetch unresolved threads

```bash
gh api graphql -f query='
{
  repository(owner: "<org>", name: "<repo>") {
    pullRequest(number: PR_NUMBER) {
      reviewThreads(first: 100) {
        nodes {
          id
          isResolved
          path
          line
          comments(first: 10) {
            nodes {
              author { login }
              body
              createdAt
            }
          }
        }
      }
    }
  }
}'
```

Replace `PR_NUMBER` with the actual number. Filter to `isResolved == false` only.

**Also always fetch review bodies** — findings that can't map to a diff line are posted as review body comments and are invisible to `reviewThreads`. This is not optional:

```bash
gh api repos/<org>/<repo>/pulls/$PR_NUMBER/reviews \
  --jq '.[] | select(.state != "DISMISSED" and .body != "" and .body != " ") | {id: .id, user: .user.login, state: .state, body: .body[0:300]}'

gh api repos/<org>/<repo>/issues/$PR_NUMBER/comments \
  --jq '.[] | {id: .id, user: .user.login, body: .body[0:300]}'
```

If no unresolved threads, no actionable review bodies, and no conversation comments, report "No unresolved review comments" and stop.

## 2. Triage each thread

For each unresolved thread:

1. Read the file at the referenced path and line
2. Read the full comment thread for context
3. Check recent commits on the branch to see if the issue was already addressed
4. Classify with a verdict:

| Verdict | Meaning |
|---------|---------|
| `[FIX]` | Valid issue, needs a code change |
| `[ALREADY ADDRESSED]` | Fixed in a recent commit on the branch |
| `[NOT RELEVANT]` | Doesn't apply (with explanation) |
| `[UNCLEAR]` | Needs user input to decide |

## 3. Present verdicts

Show all threads with their verdicts:

```text
### 1. path/to/file.py:42 — @reviewer
> Original comment text...

**Verdict: [FIX]** — Need to add null check before accessing `.name`

### 2. path/to/other.ts:15 — @reviewer
> Original comment text...

**Verdict: [ALREADY ADDRESSED]** — Fixed in commit abc1234

### 3. path/to/config.tf:8 — @bot
> Original comment text...

**Verdict: [NOT RELEVANT]** — This follows the established pattern in sibling modules
```

For `[UNCLEAR]` threads, ask the user what to do.

Wait for user confirmation before proceeding. The user may change verdicts or provide guidance.

## 4. Apply fixes

For each `[FIX]` thread, make the code change. Use Edit tool for targeted changes. Group related fixes when they touch the same file.

## 5. Resolve threads

For all threads classified as `[FIX]`, `[ALREADY ADDRESSED]`, or `[NOT RELEVANT]` (after user confirmation), resolve them via GraphQL.

**Single thread:**

```bash
gh api graphql -f query='
mutation {
  resolveReviewThread(input: {threadId: "THREAD_ID"}) {
    thread { isResolved }
  }
}'
```

**Batch resolution (2+ threads) — always prefer this when resolving multiple threads:**

```bash
gh api graphql -f query='
mutation {
  t1: resolveReviewThread(input: {threadId: "PRRT_xxx"}) { thread { isResolved } }
  t2: resolveReviewThread(input: {threadId: "PRRT_yyy"}) { thread { isResolved } }
  t3: resolveReviewThread(input: {threadId: "PRRT_zzz"}) { thread { isResolved } }
}'
```

Use GraphQL aliases (`t1`, `t2`, ...) to batch multiple mutations in a single request. Each alias can be any unique name.

**Batch minimize (2+ comments):**

```bash
gh api graphql -f query='
mutation {
  m1: minimizeComment(input: {subjectId: "PRRC_xxx", classifier: RESOLVED}) { minimizedComment { isMinimized } }
  m2: minimizeComment(input: {subjectId: "PRR_yyy", classifier: RESOLVED}) { minimizedComment { isMinimized } }
}'
```

Combine both operations in a single mutation when resolving threads AND minimizing comments:

```bash
gh api graphql -f query='
mutation {
  t1: resolveReviewThread(input: {threadId: "PRRT_xxx"}) { thread { isResolved } }
  t2: resolveReviewThread(input: {threadId: "PRRT_yyy"}) { thread { isResolved } }
  m1: minimizeComment(input: {subjectId: "PRRC_xxx", classifier: RESOLVED}) { minimizedComment { isMinimized } }
  m2: minimizeComment(input: {subjectId: "PRR_zzz", classifier: RESOLVED}) { minimizedComment { isMinimized } }
}'
```

## 6. Minimize addressed review body comments (mandatory — do not skip)

After all threads are resolved, sweep for review body comments that are addressed but not yet hidden. **This step is mandatory — do not skip even when there are no open threads.** Note: step 5 handles inline `PRRC_` comments alongside thread resolution; this step targets review body nodes (`PRR_` prefix).

```bash
gh api graphql -f query='
{
  repository(owner: "<org>", name: "<repo>") {
    pullRequest(number: PR_NUMBER) {
      reviews(first: 50) {
        nodes {
          id
          author { login }
          body
          isMinimized
        }
      }
    }
  }
}'
```

Filter to `body != ""` AND `isMinimized == false`. For each:

- Findings now addressed → minimize with `classifier: RESOLVED`
- Pure bot markup header with no actionable body → minimize with `classifier: RESOLVED`
- Open human review with unaddressed content → do NOT minimize; flag to user

Batch all in one mutation:

```graphql
mutation {
  m1: minimizeComment(input: {subjectId: "PRR_xxx", classifier: RESOLVED}) { minimizedComment { isMinimized } }
  m2: minimizeComment(input: {subjectId: "PRR_yyy", classifier: RESOLVED}) { minimizedComment { isMinimized } }
}
```

**Why**: findings on the PR body are invisible to `reviewThreads` GraphQL — only the `/reviews` endpoint exposes them. Skipping this step leaves addressed bot reviews visually open and allows unaddressed body findings to go unnoticed.

## 7. Dismiss bot reviews

Check for "Changes Requested" reviews that are now fully addressed:

```bash
gh api repos/<org>/<repo>/pulls/$PR_NUMBER/reviews \
  --jq '.[] | select(.state == "CHANGES_REQUESTED") | {id: .id, node_id: .node_id, user: .user.login}'
```

For each review where ALL threads from that reviewer are now resolved:

- **Bot reviewers** (`github-actions[bot]`, `cursor[bot]`): auto-dismiss and minimize. Prefer the GraphQL `dismissPullRequestReview` mutation which can be batched with `minimizeComment` in a single request:

  ```graphql
  mutation {
    d1: dismissPullRequestReview(input: {pullRequestReviewId: "PRR_xxx", message: "All changes addressed."}) { pullRequestReview { state } }
    m1: minimizeComment(input: {subjectId: "PRR_xxx", classifier: RESOLVED}) { minimizedComment { isMinimized } }
  }
  ```

  Alternatively, dismiss via REST (cannot be combined with GraphQL mutations):

  ```bash
  gh api repos/<org>/<repo>/pulls/$PR_NUMBER/reviews/{review_id}/dismissals \
    -X PUT -f message="All requested changes have been addressed."
  ```

  If using REST for dismiss, batch the subsequent `minimizeComment` calls for review body nodes (`PRR_` prefix) in a single GraphQL mutation (see batch patterns above).

- **Human reviewers**: inform the user and suggest requesting a re-review instead of dismissing

## Safety

- **Present all verdicts before making changes** — never fix or resolve without user confirmation
- **Never resolve a thread without addressing it** — every thread gets a verdict
- **Never silently skip a thread** — address ALL unresolved threads
- **Don't dismiss human reviews** — only auto-dismiss bot reviews; suggest re-review for humans
