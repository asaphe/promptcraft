# PR Review Policy

- **Prefer `/sdlc-review` for SDLC-tracked PRs** — When the branch follows `dev-###-*` and has a linked task, `/sdlc-review` is the comprehensive review path: it loads domain checklists, task context (acceptance criteria, design comments), and provides interactive Q&A. Falls through to the routing table below for standalone reviews without SDLC context.

- **Route reviews by file scope** — Always determine what changed before choosing a reviewer. Never do ad-hoc reviews in the main context. Spawn all applicable reviewers in parallel for mixed PRs. Tell every agent: "Don't assume — check the codebase and verify every finding before reporting it."

  | Changed files | Reviewer |
  | --- | --- |
  | `devops/`, `.github/`, `**/Dockerfile*`, `**/*.sh` | Spawn `devops-reviewer` agent |
  | `**/05-external-secrets-stores/vars/**`, `**/10-helm-values/vars/**`, `**/helm-reusable-chart/values/**` | Spawn `secrets-config-reviewer` agent |
  | ClickHouse code (handlers, SQL, migrations, dbt models, CH Terraform) | Spawn `clickhouse-reviewer` agent |
  | `.claude/` | Spawn `agent-config-reviewer` agent |
  | Application code (Python, TypeScript, Go, Java) | Spawn `general-reviewer` agent |
  | Mixed | Spawn all applicable reviewers in parallel |

- **Present findings before posting** — After the review agent returns findings, present them to the user for approval. Do not let agents post directly to the PR without review. The user may want to adjust tone, add context, or remove items before they go public.

- **Address every PR review comment — always, automatically** — When interacting with a PR in any capacity (reviewing, re-reviewing, pushing fixes, checking status), fetch and address ALL unresolved feedback without being asked. Check all four surfaces: (1) the PR body itself (description, checklists, test plan), (2) review threads (GraphQL `reviewThreads`), (3) review bodies (`gh api repos/.../pulls/{n}/reviews`), (4) conversation comments (`gh api repos/.../issues/{n}/comments`). The PR body is frequently overlooked — always read it for context, checklists, and inline questions. Address every item regardless of author — human reviewers, `github-actions[bot]`, `cursor[bot]`, or any other bot. After pushing fixes to a PR with active bot reviewers (cursor, codex-connector), wait 15-30 seconds and re-query all unresolved threads (`reviewThreads` GraphQL) before declaring clean — each push triggers new bot reviews. Resolve threads with `resolveReviewThread`, not `minimizeComment`.

- **`/pr-check` covers both CI and comments** — The `/pr-check` skill checks CI statuses AND fetches/resolves review comments in one pass. Use it when the user asks to "check the PR", "resolve comments", or "address comments". "Review the PR" means spawn reviewer agents per the routing table above — that's a different action.

- **Report all review findings at appropriate severity** — When a review identifies multiple issues, report all of them. Don't reduce findings to a single item or silently drop lower-severity ones. Every issue is worth flagging — use severity labels (blocking, warning, suggestion) to distinguish impact, but never omit findings.

- **Verify test plan items before AND after creating a PR — no empty checkboxes** — If the PR body includes a test plan with checkboxes: (1) verify each item before submitting (run tests, check syntax, validate config, wait for workflows), (2) check them off in the body with evidence (links to passing runs, verification commands used), (3) after creating the PR, wait for any auto-triggered workflows to complete and update the checkboxes with results. Never leave unchecked boxes — if a check can't be verified yet, say so explicitly rather than leaving it blank. A PR with unchecked test plan items signals unfinished work. This is a recurring issue — treat it as a hard blocker on PR submission.

- **Use `/pr-review` to review, `/pr-resolver` to fix** — When a user says "review this PR", invoke `/pr-review` (or `/sdlc-review` if the PR has SDLC context). When they say "fix the comments" or "address the review", invoke `/pr-resolver`. `/pr-check` covers CI status checks and can also triage/fix/resolve review comments — it's the all-in-one command. `/pr-resolver` is the dedicated tool when the user only wants to address review comments without CI checks.

- **Read `.claude/docs/pr-review-rules.md` before conducting a review** — Contains detailed methodology: finding verification, severity classification, tone guidelines, GitHub API usage, and common pitfalls.

- **One PR should be enough — audit comprehensively the first time** — Before opening a PR that touches a manifest, config, or list of items, audit the entire scope in one pass. For example, when adding images to the ECR manifest, search ALL consumers (tests, Dockerfiles, compose files, scripts) before opening the PR — don't add only the ones that triggered the immediate failure. A follow-up PR to fix what the first PR missed signals incomplete work.
