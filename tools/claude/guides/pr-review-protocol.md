# PR Review Protocol

Structured protocol for AI-assisted PR reviews — routing, posting, severity classification, and finding verification.

## Authorship Gate — resolve this first

**Before routing by file type, establish whether you authored the PR.** It decides what the review is allowed to do, and getting it wrong in either direction wastes the review:

| You authored it | Someone else authored it |
|---|---|
| Fix findings directly in the branch | Report only — never push to their branch |
| No review state to submit; you cannot approve your own PR | A review state is required, and it is a merge authorization |
| Self-review is a quality gate before asking for eyes | Author pushback gets re-verified, not deferred to |

Resolve it from the PR's author field, not from memory of who started the work — a branch you created can carry someone else's commits, and a PR opened on your behalf is still theirs to merge.

## Review Routing by File Scope

Once authorship is settled, determine what changed and route to the appropriate reviewer:

| Changed Files | Reviewer Type |
| ------------- | ------------- |
| Infrastructure files (`**/terraform/**`, `**/*.tf`) | Infrastructure/DevOps reviewer |
| CI/CD files (`.github/`, `**/Dockerfile*`, `**/*.sh`) | DevOps/pipeline reviewer |
| AI config files (`.claude/`, `.cursorrules`, etc.) | Config reviewer |
| Application code (Python, TypeScript, Go, Java) | Application code reviewer |
| Mixed changes | Spawn all applicable reviewers in parallel |

**Key principle:** Always determine what changed before choosing a reviewer. Never do ad-hoc reviews in the main conversation context — delegate to specialized reviewers.

For mixed PRs (e.g., application code + Terraform + GitHub Actions), spawn all applicable reviewers in parallel. Each reviewer focuses on its domain.

## Act on Reviewer Deferrals

When a reviewer agent's output contains a deferral (e.g., "defer to infrastructure reviewer", "outside my scope"), the orchestrating agent must spawn the deferred reviewer before reporting results. Deferrals are incomplete reviews, not informational notes. A deferral left unactioned means part of the PR was never reviewed.

## Present Findings Before Posting

After a review agent returns findings, **present them to the user for approval** before posting to the PR. The user may want to:

- Adjust tone or phrasing
- Add context the reviewer missed
- Remove false positives
- Change severity classifications

Never let review agents post directly to a PR without human review.

## Posting Protocol

### Post inline comments per-comment, then submit the review

Findings belong on the diff line they refer to, not in a PR-level conversation comment. **Post them one at a time**, then submit a separate review carrying the summary and the state:

```bash
# 1. One call per finding
gh api POST /repos/{owner}/{repo}/pulls/{number}/comments \
  --field commit_id="$HEAD_SHA" \
  --field path="path/to/file.tf" \
  --field line=42 \
  --field side="RIGHT" \
  --field body="Finding description here"

# 2. Then one review that sets the state and summarizes
gh pr review {number} --request-changes --body "2 blocking, 4 suggestions"
```

**Do not use `POST /pulls/{n}/reviews` with a `comments[]` array for interactive review.** That bulk path is known to silently drop inline comments — the API returns 201 and the comments never appear on the PR, which reads as a successful post. It remains reasonable in CI, where a single atomic call is worth the risk, or when posting a summary with no inline comments at all. Details and the full per-comment field set: [`../examples/docs/pr-review-posting.md`](../examples/docs/pr-review-posting.md).

The review submitted in step 2 is what groups the inline comments under a review event and sets the state visible on the PR page; without it they sit as loose comments.

**The review state is a merge authorization, not a tone — pick it from your findings.** The example above uses `--request-changes` for illustration; it is not a default. Choose from what you want to happen, never by looking up the highest severity present:

| Your findings | `event` |
|---|---|
| Anything you want changed before merge | `REQUEST_CHANGES` |
| Informational only, but you don't want to authorize merge | `COMMENT` |
| You would accept it merging exactly as-is | `APPROVE` |

**"Approve with comments" is not a GitHub state.** Submitting `APPROVE` with a body full of things you want fixed says merge and don't-merge in the same breath, and the author acts on the state. Before submitting, re-read your own draft for that shape: a sentence like "I'd like this fixed first" inside an `APPROVE` is the tell.

Three rationalizations each produce a wrong `APPROVE`, and all three are rejected: *another reviewer already blocks it so mine is costless* (their block can be dismissed without your finding ever being revisited); *blocking is disproportionate for a small or docs-only change* (proportionality governs how much you write, never which state you pick); *that file is another team's surface* (approval is repo-wide, not per-file — not owning the file argues for `COMMENT`).

**Avoid:** `gh pr review --comment --body` for large markdown — it can fail silently or double-post. The API gives reliable control.

### Only Report Problems

Review output should contain only blocking issues and suggestions. Do not include a "GOOD" or "positive findings" section — it dilutes actionable feedback with noise.

### Delete Wrong Comments

If a posted review comment is found to be incorrect, **delete it** rather than replying with a correction:

```bash
gh api repos/{owner}/{repo}/pulls/comments/{id} --method DELETE
```

Replying to your own comment with "actually, this was wrong" creates noise and confusion. Delete the incorrect comment and post a new one if a corrected finding is needed.

### Atomic Comment Resolution

When you change code in response to a review comment, the unit of work is **fix + reply + resolve**, performed atomically — never just the code fix. The most common review-followup mistake is a model that pushes the code change and stops, leaving the reviewer to scroll through a wall of unresolved threads to figure out which were addressed.

The three actions in order:

1. **Fix the code** — change the file, commit, push.
2. **Reply on the thread** — one short comment per thread explaining what was done. For comments not relevant to the diff or already addressed by other changes, reply with that verdict. Don't leave a fixed thread without a reply — the reviewer can't tell from a `git diff` alone.
3. **Resolve the thread** — `resolveReviewThread` GraphQL mutation (see below). `gh pr comment` does NOT resolve threads; resolution is a distinct API call.

A useful shorthand: "address all review comments" is shorthand for **all three actions per comment**, not just the code change. Treating the code change as the whole task is the bug.

### Resolve Threads via GraphQL

The GitHub REST API does not support resolving PR review threads. Use GraphQL:

```graphql
# Query thread IDs
{
  repository(owner: "<owner>", name: "<repo>") {
    pullRequest(number: <number>) {
      reviewThreads(first: 100) {
        nodes { id isResolved }
      }
    }
  }
}

# Resolve a thread
mutation {
  resolveReviewThread(input: { threadId: "<thread-id>" }) {
    thread { isResolved }
  }
}
```

### Hide / Minimize Bot Comments

Use `minimizeComment` to collapse addressed or irrelevant bot comments. It works on all three GitHub node types:

| Node prefix | Type | Example |
|-------------|------|---------|
| `PRRC_` | Inline review comment | Cursor, CodeQL inline finding |
| `IC_` | Issue / PR body comment | Codex, bot conversation comment |
| `PRR_` | PR review body | github-actions review summary |

```graphql
mutation {
  minimizeComment(input: { subjectId: "<node-id>", classifier: RESOLVED }) {
    minimizedComment { isMinimized }
  }
}
```

Available classifiers: `RESOLVED`, `OUTDATED`, `DUPLICATE`, `OFF_TOPIC`, `SPAM`, `ABUSE`.

For bot inline threads: use **both** `resolveReviewThread` (hides the thread) **and** `minimizeComment` (collapses the comment in the timeline). For review-body comments (`PRR_`) and issue comments (`IC_`), `minimizeComment` alone is sufficient.

## Severity Classification

### Blocking vs Suggestion

| Severity | Meaning | Examples |
| -------- | ------- | -------- |
| **Blocking** | PR should not merge without fixing this | Security vulnerability, data loss risk, broken functionality, clear spec violation |
| **Issue** | Real problem, should fix — not merge-blocking | Silent failures, privilege escalation, fragile patterns, error handling gaps |
| **Suggestion** | Worth considering but not merge-blocking | Performance optimization, code style improvement, future-proofing, migration opportunity |

**Issue vs Suggestion:** If you'd file a bug for it, it's at least an Issue. Suggestions are "nice to have" — Issues are real problems that won't prevent merge but deserve attention.

**These three are what you post.** Grading a finding before posting it — including the `GAP` category for work the change implies but did not do, which otherwise gets miscategorised as cosmetic and skipped — is covered in [`../examples/rules/general/review-verdicts.md`](../examples/rules/general/review-verdicts.md), along with the map from those grades onto the three severities above.

### Finding Type Classification

Every finding title should include both severity and finding type:

```text
ISSUE-1: Wrong value — image tag doesn't match deployed version
BLOCKING-1: Missing port — service unreachable on health check endpoint
SUGGESTION-1: Pattern violation — naming inconsistent with sibling modules
```

Standard finding types (each maps to specific verification steps):

| Type | Verify by |
|------|-----------|
| Wrong value | Query the real system for the actual value |
| Missing X | Grep codebase + check 3+ sibling files |
| Security issue | Trace data flow, show concrete attack vector |
| Config mismatch | Read both sides, show the comparison |
| Pre-existing issue | `git blame` to confirm, downgrade to Issue |
| Dead code | Grep all consumers including dynamic references |
| Pattern violation | Check 3+ siblings for established convention |
| Performance issue | Identify the code path, estimate production scale |

This classification serves two purposes: it forces the reviewer to think about *what kind* of problem they're reporting (which determines how to verify it), and it gives the author an immediate signal about what's wrong.

### Hypothetical-Future Observations = Suggestions

Observations about what **could** break if the code is extended later (e.g., "if you add push triggers, this concurrency group would collide") are valid as suggestions — they give the author useful context. Never classify them as blocking or frame them as something that needs to change now.

### Spec MUST + Widespread Non-Compliance = Suggestion

When a project spec says "MUST" but multiple existing files violate it (e.g., missing `outputs.tf` when 4+ modules also lack it), classify as **suggestion** with a migration-opportunity note, not blocking.

Blocking means "this PR should not merge without fixing this." If the codebase has lived without it, it's not merge-blocking for this PR.

## Suggestive Tone When Intent Is Unknown

When reviewing code where the author's intent isn't clear, use suggestive language:

| Instead of... | Use... |
| ------------- | ------ |
| "Add error handling here" | "Worth considering error handling here" |
| "Change this to X" | "You might want to use X because..." |
| "This is wrong" | "This might not behave as expected because..." |

Reserve directive language ("add this", "change this", "this must be") for clear standards violations where intent is unambiguous.

## Finding Verification Protocol

Review agents produce false positives. Before presenting findings to the user (or posting to GitHub), verify each one:

### 1. Check Codebase Patterns

Check sibling files and resources for the same pattern. If the "violation" is the established norm across the codebase, downgrade to suggestion or drop entirely.

### 2. Verify Domain-Specific Claims

For claims about specific technologies (database syntax, language idioms, framework behavior, cloud provider APIs), verify via official docs or source code — not model knowledge.

### 3. Validate Severity

A real issue at wrong severity wastes the author's time just like a false positive. A "blocking" finding that turns out to be cosmetic erodes reviewer credibility.

### 4. Verify External Claims

AWS runtimes, action versions, API behaviors, and service capabilities change over time. Before flagging something as blocking based on external knowledge (e.g., "this runtime is unsupported"), verify against current documentation. Do not rely on memorized knowledge for these claims.

### 5. Spec Is Authoritative Over Convention

When reviewing, always check the project spec (e.g., CI/CD spec, coding standards). If existing code violates the spec, the spec wins — flag the violation for migration, don't suggest the PR match the existing (incorrect) convention.

### 6. Dereference Tags When Verifying Pinned Versions

When verifying action or dependency version pins, be aware that annotated tags may have different object SHAs than the commit they point to. Always dereference to the commit SHA before flagging a mismatch.

## Shared Module Check

When a PR creates inline cloud resources (S3 buckets, IAM roles, queues, etc.), check whether the organization's shared modules repo already has a module that should be used instead. Also check if a repeating pattern across files should be extracted to a shared module.
