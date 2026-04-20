# PR Workflow Rules

- **After conflict resolution or rebase, verify CI passes before declaring done** — Rebasing and conflict resolution can introduce subtle breakage. After any rebase or merge conflict resolution, monitor CI until all checks pass. Do not declare the PR ready until green.

- **Resolve human review threads with `resolveReviewThread`** — `resolveReviewThread` (thread ID prefix `PRRT_`) is the correct mutation for resolving PR review conversations. `minimizeComment` alone is NOT sufficient — it collapses the comment visually but leaves the thread unresolved. For human review threads: use `resolveReviewThread` only. For bot comments (CodeQL, Bugbot, etc.): use BOTH `resolveReviewThread` AND `minimizeComment` — see `pr-bot-comments.md` for the bot-specific workflow.

- **Cleanup is part of addressing findings — never stop at the code fix** — After fixing or dismissing a review finding, immediately: (1) dismiss CHANGES_REQUESTED reviews with `dismissPullRequestReview`, (2) minimize all review body nodes with `minimizeComment` (`PRR_` prefix), (3) resolve all inline threads with `resolveReviewThread` (`PRRT_` prefix). Leaving threads open and review bodies visible after addressing them is an incomplete response — the PR timeline must reflect current state.

- **Self-review with the appropriate reviewer agent before pushing** — When creating new files or fixing code, spawn the relevant reviewer agent before committing. This applies to both reactive work (fixing a review comment) and proactive work (authoring new content). Route by file type: `devops-reviewer` for Dockerfiles/workflows/terraform/shell, `agent-config-reviewer` for `.claude/` rules/agents/skills, `general-reviewer` for application code. Quick fixes and new content are both high-risk for quality gaps — the reviewer catches what the author misses.

- **Address ALL review findings when asked — never self-triage** — When asked to fix or address PR review comments, treat every finding as actionable — including those labeled "suggestion", "pre-existing", or "not introduced by this PR". Do not silently dismiss findings as "not a blocker", "out of scope", or "pre-existing". For findings that are clearly in-scope for the current PR, fix them directly. For pre-existing or tangential findings, ask the user whether to address them in the current PR or open separate PRs. If a finding genuinely cannot be addressed (e.g., breaking change requiring coordinated updates), explain why and ask — do not skip it.

- **Verify all findings before posting to a PR** — PR review comments are permanent and visible to the whole team. Before posting any finding, independently re-check it against the actual code or codebase. A wrong finding damages reviewer credibility and costs more time to clean up than it saves. When in doubt about accuracy, drop or downgrade the finding rather than post it speculatively.

- **Check BOTH PR body and inline comments when resolving** — When triaging or resolving PR review comments, check both the inline file comments AND the PR body/conversation comments. Missing one location leaves findings unaddressed.

- **Post review comments inline on files, not as PR conversation** — Review findings must be posted as inline comments on the specific file and line, not as general PR conversation comments. If no specific line applies, ask the user where to place the comment. Never post duplicate comments.

- **Update PR body checkboxes after completing verification** — After verifying each item in a PR checklist, immediately update the PR body to check the corresponding box. Only include checkboxes for items that can be verified programmatically — if you can't check it, don't list it.

- **Review full files in context, not just the diff** — When reviewing a PR, examine the full files to understand context, not just the changed lines. The diff alone can miss issues only visible in the broader file (e.g., duplicate logic, inconsistent patterns, missing imports).

- **Minimize or delete wrong comments — never reply to self-correct** — When a review comment you posted is wrong, use `minimizeComment` to hide it. Do not reply to your own comment to "correct" it — that creates noise. Clean up the mistake, don't add to it.

- **Batch GraphQL mutations when resolving multiple threads** — Use aliased mutations in a single `gh api graphql` query instead of one call per thread. A PR with 10 threads should resolve in 1-2 API calls, not 10-20.
