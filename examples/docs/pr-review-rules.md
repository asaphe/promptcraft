# PR Review Methodology

Detailed rules for conducting PR reviews. Read this file when performing a review — it covers finding quality, severity classification, GitHub API usage, and common pitfalls.

## Diff Scope Enforcement

- **NEVER comment on files outside the PR diff** — Before posting any inline comment, verify the target `path` appears in `gh pr diff --name-only`. This is a hard constraint, not a suggestion. Reading adjacent files for context is fine, but findings on files not in the diff must be mentioned in the summary body (if critical) or dropped entirely. A comment on a non-diff file is a 422 API error at best and a hallucinated false positive at worst.

- **The diff file list is pre-computed and injected into your system prompt** — The CI workflow pre-computes `gh pr diff --name-only` and injects the result as `CHANGED_FILES` in your system prompt. Use this list as your authoritative allowlist — do not re-compute it. Before constructing each inline comment, check that its `path` exists in that list. A post-review cleanup step will delete any comments on non-diff files as a safety net, but prevention is always preferred.

## Finding Quality

- **Verify every finding against codebase patterns and primary sources** — Review agents produce false positives. Before presenting findings to the user (or posting to GitHub), independently verify each one: (a) check sibling files and resources for the same pattern — if the "violation" is the established norm, downgrade to suggestion or drop entirely; (b) for domain-specific claims (ClickHouse syntax, Go idioms, Python async patterns, Terraform behavior), verify via official docs or source code, not model knowledge; (c) validate severity — a real issue at wrong severity wastes the author's time just like a false positive. A finding that survives verification is credible; one that doesn't should never reach the PR.

- **Verify external claims before classifying as blocking** — AWS runtimes, action versions, API behaviors, and service capabilities change over time. Before flagging something as blocking based on external knowledge (e.g., "this runtime is unsupported", "this API doesn't support X"), verify against live docs using WebFetch. Do not rely on memorized knowledge for these claims. A wrong "blocking" finding wastes the author's time and erodes reviewer credibility.

- **Only report problems — skip "GOOD" sections** — Review output should contain only findings. Do not include a "GOOD" or "positive findings" section — it's noise that dilutes actionable feedback.

## Severity Classification

Three severity levels, from highest to lowest:

| Severity | Meaning | GitHub event | When to use |
|----------|---------|--------------|-------------|
| **BLOCKING** | Must fix before merge | `REQUEST_CHANGES` | Bugs, security issues, data loss, broken contracts |
| **ISSUE** | Real problem, should fix — not merge-blocking | `COMMENT` | Silent failures, privilege escalation, fragile patterns, error handling gaps |
| **SUGGESTION** | Nice to have, style, minor improvement | `COMMENT` | Code style, consolidation opportunities, defensive hardening |

- **ISSUE is for real problems that won't prevent merge but should be addressed** — If a finding describes something that will cause user-facing confusion, debugging difficulty, or silent data loss in edge cases, it's an ISSUE — not a SUGGESTION. The test: would you file a bug for it? If yes, it's at least an ISSUE.

- **Hypothetical-future observations are suggestions, not issues** — Observations about what could break if the code is extended later (e.g., "if you add push triggers, this concurrency group would collide") are valid as suggestions — they give the author useful context. Never classify them as ISSUE or BLOCKING.

- **Spec MUST + widespread non-compliance = suggestion, not blocking** — When a spec says "MUST" but multiple existing modules violate it (e.g., missing `outputs.tf` when 4+ modules also lack it), classify as suggestion with a migration-opportunity note, not blocking. Blocking means "this PR should not merge without fixing this." If the codebase has lived without it, it's not merge-blocking for this PR.

- **Spec is authoritative over existing convention** — When reviewing, always check the project spec (e.g., ci-cd-spec.md). If existing code violates the spec, the spec wins — flag the violation for migration, don't suggest the PR match it. If you spot a pattern where many files violate the spec, flag it as a migration opportunity rather than accepting the violation as convention.

## Tone

- **Suggestive tone when intent is unknown** — When reviewing code where the author's intent isn't clear, use suggestive language ("worth considering", "you might want to") rather than prescriptive ("add this", "change this"). Reserve directive language for clear standards violations.

## GitHub API

- **Post findings as inline file comments only** — Use `gh api POST /repos/{owner}/{repo}/pulls/{number}/comments` to post each finding on the exact line it refers to (params: `path`, `line`, `body`, `commit_id`, `side`). Do not post a review body or summary unless the user explicitly asks for one. If a finding can't be mapped to a specific line, ask the user where to place it before falling back to a PR-level conversation comment.

- **Dereference annotated tags when verifying action SHAs** — GitHub's `git/ref/tags/{name}` API returns the tag object SHA for annotated tags, not the commit SHA. Actions pin to the commit SHA. To verify: use `gh api repos/{owner}/{repo}/tags --jq '.[] | select(.name == "{tag}") | .commit.sha'` which returns the commit SHA directly. Do not flag a mismatch without dereferencing first.

- **Delete wrong comments — never reply-correct your own** — If a posted review comment is found to be incorrect, delete it via `gh api repos/{owner}/{repo}/pulls/comments/{id} --method DELETE`. Do not reply to your own comment with a correction — it creates noise and confusion. If a corrected finding is needed, post a new inline comment on the same file and line via the Reviews API. Only use a PR-level conversation comment if the original was PR-level.

- **Remove accidental review bodies by blanking** — Submitted reviews cannot be deleted via the GitHub API. To remove an unwanted review body, blank it with `gh api repos/{owner}/{repo}/pulls/{number}/reviews/{id} -X PUT -f body=" "`. If the review was `CHANGES_REQUESTED` or `APPROVED`, dismiss it first with `gh api repos/{owner}/{repo}/pulls/{number}/reviews/{id}/dismissals -X PUT -f message="..."`, then blank the body.

- **Resolve review threads via GraphQL, not REST** — The GitHub REST API does not support resolving PR review threads. Use the GraphQL `resolveReviewThread` mutation: first query `pullRequest { reviewThreads(first: 100) { nodes { id isResolved } } }` for thread IDs, then `mutation { resolveReviewThread(input: { threadId: "..." }) { thread { isResolved } } }` for each thread.

## Terraform-Specific

- **tf-modules check on every TF review** — When a PR creates inline AWS resources (`aws_s3_bucket`, `aws_iam_role`, `aws_iam_policy`, `aws_sqs_queue`, etc.), check whether the shared `tf-modules` repo already has a module that should be used instead (`aws/s3`, `aws/iam/role`, `aws/iam/policy`, `aws/sqs`, etc.). Also check if a repeating pattern across files should be extracted to a new tf-module.

## Test Plans

- **Test plans must be concrete and resolved** — Every test plan item must be testable in the current context with a verifiable outcome. Check boxes as you verify each item. Remove items that can't be tested (aspirational checks, external-tool-dependent validations). Open checkboxes signal the PR isn't ready; fully checked boxes signal testing was done, not deferred.
