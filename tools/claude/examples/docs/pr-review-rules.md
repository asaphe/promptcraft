# PR Review Methodology

Detailed rules for conducting PR reviews. Read this file when performing a review — it covers diff scope, finding quality, severity classification, GitHub API usage, and common pitfalls.

This file is a kernel: the rules here apply to every reviewer agent. Per-repo overlays may add domain-specific verification rows that extend it (e.g. a `pr-review-rules.md` next to this file in a downstream repo). Keep the kernel and its overlays in sync; byte-equality is a convention until a CI drift check lands.

## Diff Scope Enforcement

- **NEVER comment on files outside the PR diff** — Before posting any inline comment, verify the target `path` appears in `gh pr diff --name-only`. This is a hard constraint, not a suggestion. Reading adjacent files for context is fine, but findings on files not in the diff must be mentioned in the summary body (if critical) or dropped entirely. A comment on a non-diff file is a 422 API error at best and a hallucinated false positive at worst.

- **The diff file list is pre-computed and injected into your system prompt** — A CI workflow can pre-compute `gh pr diff --name-only` and inject the result as `CHANGED_FILES` in the agent's system prompt. Use this list as your authoritative allowlist — do not re-compute it. Before constructing each inline comment, check that its `path` exists in that list. A post-review cleanup step will delete any comments on non-diff files as a safety net, but prevention is always preferred.

## Finding Quality — Evidence-Based Review

- **Every finding requires an Evidence block** — No finding is valid without showing what was checked and what was found. See `pr-review-verification.md` for the evidence format and type-specific verification checklists. "I verified this" is not evidence — show the command, query, or file read and its result.

- **Two-pass review: scan then verify** — Pass 1: read the diff and full files, collect potential findings. Pass 2: for each potential finding, follow the verification checklist for its type (wrong value → query real system, missing X → search 3+ siblings, security → trace data flow). Drop findings that fail verification. Specifically: (a) check sibling files for the same pattern — if the "violation" is the established norm, downgrade or drop; (b) for domain-specific claims, verify via official docs or source code, not model knowledge; (c) validate severity — wrong severity wastes time like a false positive. A finding that survives verification is credible; one that doesn't should never reach the PR.

- **"Observation" is not a lower-verification severity** — Labeling a finding as "observation" or "the author should confirm" does not exempt it from verification. If a claim is worth reporting, it's worth verifying — trace the dependency, run the import, read the config. If you can't verify it, don't report it as an observation — either investigate further or drop it. Unverified observations train the reviewer to accept "plausible but wrong" findings. Every finding presented to the author must be backed by evidence, regardless of severity label.

- **Verify external claims before classifying as blocking** — AWS runtimes, action versions, API behaviors, and service capabilities change over time. Before flagging something as blocking based on external knowledge (e.g., "this runtime is unsupported", "this API doesn't support X"), verify against live docs using WebFetch. Do not rely on memorized knowledge for these claims. A wrong "blocking" finding wastes the author's time and erodes reviewer credibility.

- **Only report problems — skip "GOOD" sections** — Review output should contain only findings. Do not include a "GOOD" or "positive findings" section — it's noise that dilutes actionable feedback.

- **Classify the finding type in the title** — Every finding title must include both severity and finding type: `ISSUE-1: Wrong value — <description>`, `BLOCKING-1: Missing X — <description>`. Finding types match `pr-review-verification.md` sections: wrong value, missing X, security issue, doesn't match config/spec, pre-existing issue, dead code, pattern violation, CI step will fail at runtime, trigger condition doesn't match real dependency. The type determines which verification steps apply. Repo overlays may add domain-specific types (e.g. performance issue); check for an adjacent `pr-review-verification.md` for additions.

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

- **Spec is authoritative over existing convention** — When reviewing, always check the project spec. If existing code violates the spec, the spec wins — flag the violation for migration, don't suggest the PR match it. If you spot a pattern where many files violate the spec, flag it as a migration opportunity rather than accepting the violation as convention.

## Tone

- **Suggestive tone when intent is unknown** — When reviewing code where the author's intent isn't clear, use suggestive language ("worth considering", "you might want to") rather than prescriptive ("add this", "change this"). Reserve directive language for clear standards violations.

## Review Process

- **Read files from the PR branch HEAD, not the patch diff** — `gh pr diff` shows cumulative changes but early hunks may reflect intermediate commits, not the final state. Always `git fetch` the branch and `git show <branch>:<file>` to read the actual current code.

- **De-duplicate against existing PR comments before posting** — Read all inline comments (bot + human) before drafting findings. If a finding is already stated by another reviewer, don't repost it. **Always fetch comments with `{id, author, body}` — never `.body` alone.** Fetching only `.body` concatenates all bodies in sequence with no delimiter; it's trivially misread as one message and has caused misattributed findings (e.g. assuming an author copied a bot's text when they were just sequential outputs).

- **Read each existing comment individually before labeling it stale** — When characterizing pre-existing bot/reviewer comments as outdated, fetch and read each one independently. A blanket "all three reference the old version" claim is usually wrong for at least one comment. State specifically what each comment references and why it's stale or addressed.

- **Check for redundant event triggers** — When a workflow has multiple triggers that can fire for the same real-world action (e.g. `push.tags` + `release: [published]` both fire when a release is created with a new tag), flag the redundancy. With `cancel-in-progress: true`, the second trigger cancels the first mid-run — amplified by any multi-step sequential work added by the PR.

- **Review full files**, not just diffs. Context reveals duplicates, inconsistent patterns, missing imports.

## GitHub API

- **Use `line` + `side`, not `position`, for inline review comments** — The `position` parameter counts lines from the diff hunk header and easily lands on removed code. Use the review submission API with `line` (file line number) and `side: "RIGHT"`.

- **Post findings as inline file comments only** — Use `gh api POST /repos/{owner}/{repo}/pulls/{number}/comments` to post each finding on the exact line it refers to (params: `path`, `line`, `body`, `commit_id`, `side`). Do not post a review body or summary unless the user explicitly asks for one. If a finding can't be mapped to a specific line, ask the user where to place it before falling back to a PR-level conversation comment.

- **Dereference annotated tags when verifying action SHAs** — GitHub's `git/ref/tags/{name}` API returns the tag object SHA for annotated tags, not the commit SHA. Actions pin to the commit SHA. To verify: use `gh api repos/{owner}/{repo}/tags --jq '.[] | select(.name == "{tag}") | .commit.sha'` which returns the commit SHA directly. Do not flag a mismatch without dereferencing first.

- **Delete wrong comments — never reply-correct your own** — If a posted review comment is found to be incorrect, delete it via `gh api repos/{owner}/{repo}/pulls/comments/{id} --method DELETE`. Do not reply to your own comment with a correction — it creates noise and confusion. If a corrected finding is needed, post a new inline comment on the same file and line via the Reviews API. Only use a PR-level conversation comment if the original was PR-level.

- **Remove accidental review bodies by blanking** — Submitted reviews cannot be deleted via the GitHub API. To remove an unwanted review body, blank it with `gh api repos/{owner}/{repo}/pulls/{number}/reviews/{id} -X PUT -f body=" "`. If the review was `CHANGES_REQUESTED` or `APPROVED`, dismiss it first with `gh api repos/{owner}/{repo}/pulls/{number}/reviews/{id}/dismissals -X PUT -f message="..."`, then blank the body.

- **Resolve review threads via GraphQL, not REST** — The GitHub REST API does not support resolving PR review threads. Use the GraphQL `resolveReviewThread` mutation: first query `pullRequest { reviewThreads(first: 100) { nodes { id isResolved } } }` for thread IDs, then `mutation { resolveReviewThread(input: { threadId: "..." }) { thread { isResolved } } }` for each thread.

## Test Plans

- **Test plans must be concrete and resolved** — Every test plan item must be testable in the current context with a verifiable outcome. Check boxes as you verify each item. Remove items that can't be tested (aspirational checks, external-tool-dependent validations). Open checkboxes signal the PR isn't ready; fully checked boxes signal testing was done, not deferred.

- **Test plans must include edge cases and negative tests** — Happy-path-only test plans miss the bugs that matter. For scripts that generate artifacts: test with inputs containing format-breaking characters (`|`, `"`, multi-byte UTF-8). For validators/checkers: deliberately introduce a drift and confirm the validator catches it. For cross-platform scripts: if CI runs a different bash/OS version than local, verify output matches on both. "It runs without error" is not a test — "it produces correct output with adversarial inputs" is.
