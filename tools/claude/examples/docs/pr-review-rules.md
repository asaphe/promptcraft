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

- **Same-pattern blast radius — when you flag a wrong pattern, grep the diff for siblings** — When a finding identifies a pattern that's wrong (bash redirection, shell quoting, error-handling shape, type assertion, missing guard, etc.), do not report the single instance. Run a pattern search against the entire PR diff (not just the flagged file) and flag every instance in a single finding, or as related findings cross-referenced to one root. A wrong pattern that exists in three places will read like three separate problems to a human reviewer; flagging it once is incomplete. The reviewer's job is to enumerate the blast radius — the author's job is to fix it. Bot reviewers do this naturally because they scan the whole diff; agent reviewers must do it deliberately. Canonical example: `gh api ... 2>&1 >/dev/null` (only captures stderr, misses stdout-borne error bodies) vs. `gh api ... >"${F}" 2>&1` (combined). If one instance is wrong, search the diff for all `gh api` invocations and check each.

    **Authors apply the parallel discipline before pushing a fix.** When addressing a review finding that fingers a wrong pattern, fetch and grep the entire PR diff against the merge-base — `git fetch origin main --quiet && git diff origin/main...HEAD | grep -nE '<pattern>'` — and fix every instance the grep returns. Use three-dot and `origin/main` (not two-dot or local `main`) so the diff matches what `gh pr diff` shows and isn't polluted by inverse diffs from upstream commits on a stale branch. Bot reviewers scan the whole diff post-push and will catch missed siblings; running this grep before pushing saves the round trip.

- **Producer/consumer contract coherence — flag when one file constructs a value the other validates with mismatched rules** — When one script/module constructs an identifier (deployment name, secret path, branch ref, file name, etc.) and another script/module validates or consumes it, their rules must be coherent. The consumer's accepted-set must be a superset of every value the producer can construct, or both must reference a shared constant. Two specific failure modes: (a) producer's regex/length is laxer than consumer's, so the producer can mint values the consumer rejects (consumer dead-ends, can't clean up, throws errors mid-flow); (b) producer doesn't validate at all, relying on the consumer to reject — but if rejection happens after a side-effect (branch creation, file write, API call), the side-effect leaks. Verification: trace the value from construction to consumption; check both ends have explicit constraints; if the constraints differ, flag as ISSUE with the specific mismatch (e.g., "producer allows 35 chars; consumer regex caps at 30"). Canonical example: an auto-generated deployment name constructed without length validation, against a cleanup cron that skips names longer than 30 chars — orphan reservations become permanently uncollectible.

- **Flag multi-line WHY comments in code as belonging in docs** — When a finding is "this `# ...` block (or `// ...`, `/* ... */`) of 2+ lines explains rationale that would be more discoverable in a checked-in doc", flag as SUGGESTION. Substance belongs in `CLAUDE.md`, a topic-specific doc under `.claude/docs/`, README, or PR body. Inline comments should be single-line WHY and may reference a doc (e.g., `# Must match cleanup script's NAME_RE — see <doc>`). This applies to YAML, Python, Bash, TypeScript, Go, Java — any language where a multi-line comment can leak into the diff. Carve-outs: module/class/function docstrings (Python), composite-action `description:` fields (YAML), suppression/directive comments (`# zizmor: ignore[X]`, `# noqa`, `// eslint-disable-next-line`), and toolchain/schema bindings (`# yaml-language-server: $schema=...`, package-shebang `#!/usr/bin/env bash`). Verification: count the comment's line span; if ≥2 lines and the carve-out list doesn't apply, the rationale belongs in a doc.

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

- **Weigh cost against benefit for additions** — New abstractions, dependencies, IAM permissions, config values, and CI jobs carry ongoing maintenance cost or security surface. When the benefit is unclear relative to the cost, flag as SUGGESTION. When the cost is high (wildcard permissions, complex abstraction layers, third-party dependencies, broad-scope IAM) and the benefit is marginal, escalate to ISSUE. The question to ask: "Does this change leave the system better than it found it, accounting for ongoing maintenance?"

## Default-Skeptical Disposition

The reviewer's default posture is skeptical, not charitable. Charitable framing ("the author probably meant", "consistent with the existing pattern") absorbs the burden of proof that the diff should carry.

- **Comparative claims need inline citations from the diff** — "Consistent with the existing pattern", "matches what's done in module X", and "follows the codebase convention" are claims about other code. They are not credible without an inline path-and-line citation (e.g., `path/file.ext:42-58`) showing the comparison. A reviewer reciting "consistent" without a citation is mirroring the PR body, not verifying.

- **"Consistent posture" is not a finding-dismissal axis** — When a PR claims symmetry with an existing surface (sibling module, sibling workflow, sibling IAM role), the reviewer's job is to verify the symmetry per axis, not to accept the framing. Each contract surface (trust principal, secret ARN scope, parameter path scope, environment scope, role/binding name, blast radius if compromised) is independently load-bearing — a yes on one axis does not imply yes on the others. Treat each axis as its own finding-or-no-finding decision.

- **Per-axis positive evidence is required, not absence-of-failure on one axis** — A clean output from one verification step (e.g., `terraform plan` shows no destructive changes) is not evidence that the other axes are correct. For security/infra reviews, list the axes upfront and produce positive evidence for each. Missing axes default to "not verified" — not "fine".

- **High-confidence findings need not be hedged into oblivion** — When a finding has direct evidence (cited file/line, command output, doc reference), state it directly with severity. The verification floor exists so credible findings can be presented with confidence; "you might consider" hedging on a verified bug is the rose-tinted failure mode in a different costume.

- **Precedent does not authorize a current finding-dismissal** — "We accepted this pattern in PR #N" is not a reason to dismiss the same issue here. The earlier PR may itself have been an under-reviewed precedent; surfacing it now is correct even if late. If a precedent should stand, the dismissal needs current evidence (this is acceptable for reason X), not historical evidence (this was acceptable before).

- **Scope-narrowing doesn't reduce rigor** — A request like "focus on the CI changes" means maximum depth on the named files, NOT skipping the others. Narrowed scope concentrates attention; it never licenses lower verification standards on the rest of the diff.

## Steelman Output Section (mandatory)

This is the output artifact of the [Adversarial Pass](#adversarial-pass-mandatory-after-pass-2) below — that section governs how to find issues; this section governs how to present them. Every review output includes a section titled exactly `## Steelman against the change` (canonical heading — no alternatives, no rewording) immediately after the per-file findings. The canonical heading is required so harness/orchestrator-level detection can grep for an exact string.

- **Section content** — At least one credible failure mode per modified file (or per modified contract surface for IaC), framed as the strongest case against the diff a hostile reviewer would make. "No concerns" is allowed only when the diff is genuinely trivial (e.g., README typo) — and in that case, state so explicitly rather than omitting the section.

- **Coverage axes for IaC/security reviews** — For PRs touching IAM, OIDC, secrets, parameter stores, KMS, RBAC, or workload identity: enumerate the contract surfaces and produce a steelman line per surface — even when the verdict is "no finding". The domain-specific axis list lives in the corresponding reviewer agent body (e.g., `security-reviewer.md` for IAM/OIDC/RBAC axes). The kernel-illustrative list (trust principal scope, action wildcards, resource ARNs, condition keys, environment scope, name collision risk, blast radius if compromised) covers the security-domain default.

- **No section, no review** — A review output that omits the Steelman section is incomplete. If the reviewer agent notices the section is absent in its own output before returning, it must produce it before returning. Harness-level retry on absent sections is a follow-up enforcement layer — the rule binds the reviewer, not the orchestrator.

## User-Prompt Skepticism — first-class input

When the user expresses skepticism about a verdict ("are you sure?", "take off your rose-tinted glasses", "look again at axis X"), that prompt is finding-equivalent input, not a request to re-explain the prior verdict.

- **Lean MORE adversarial after user skepticism, not the same amount** — The user has observed something the verdict missed, even if they can't articulate the specific gap. The correct response is a fresh adversarial pass that explicitly enumerates the axes that were not positively verified the first time, not a re-statement of the prior conclusions with stronger hedging.

- **Per-axis evidence on re-review, not summary** — A re-review prompted by user skepticism must produce per-axis verification artifacts (the cited path:line, the command output, the doc quote) — not a paragraph asserting "I re-checked and it's still fine". Summary without artifacts is the prior verdict in a different sentence.

- **"Your instinct is partially wrong" framing is forbidden** — When the user's instinct conflicts with the verdict, the reviewer's job is to produce evidence, not to grade the user's instinct. Frames like "you're partially right but..." or "the underlying concern is valid but the specific claim is wrong" pre-bias the re-review toward defending the prior verdict. State what was checked, what was found, and let the user judge.

- **User skepticism + security-sensitive paths = re-run via the specialist reviewers** — If user skepticism lands on a PR that touches IAM/OIDC/secrets/KMS/RBAC paths and the prior review was manual/ad-hoc, the correct response is to dispatch the specialist reviewer agents (e.g., `security-reviewer` for IAM/OIDC/RBAC/KMS, `devops-reviewer` for CI/Helm/IaC) — pick whichever matches the touched paths; multi-domain diffs dispatch all that apply — via the `/pr-review` skill rather than continue the manual thread. Reviewer inventory varies per repo; the dispatcher must skip nonexistent agents gracefully. The specialist agents enforce per-axis evidence; manual re-review re-enters the same charitable-framing failure mode.

## Mandate-Wiring Audit (rule-adding PRs)

A recurring pattern in rule-adding PRs: the diff adds a `MUST`/`MANDATORY`/`REQUIRED` clause to a kernel rule or agent body, but the implementing layer that would enforce it (the review skill's verification gate, the presentation template, the dispatch registry, the specialist-list parity in cross-reference sentences) is not updated in the same diff. The mandate ships without enforcement, and the next review run silently drops it.

- **For any PR that touches `.claude/agents/*.md`, `.claude/docs/pr-review-*.md`, or the review skill definition and adds a new mandate clause**: the diff MUST also include the wiring at the named implementer. If an agent body says "the coordinator MUST X" or the kernel says "every review output includes Y", the coordinator/presentation file must also be in the diff with the wiring change. Cross-reference parity (a sentence that names a specialist list, a path list, an axis list) must be checked against the canonical list elsewhere in the kernel — drift between path triggers and specialist routes is the same failure mode as missing coordinator wiring.

- **Self-review check** — Before requesting human review on a rule-adding PR, grep the diff for `MUST|MANDATORY|REQUIRED|coordinator MUST|every review output|the harness`. For each hit, identify the named implementer and confirm its file is also in the diff. If the mandate's implementer is not touched, either add the wiring or downgrade the mandate to a SHOULD with explicit "not yet wired — follow-up ticket" annotation.

- **Class-enumeration on fix** — When a finding identifies a single instance of a wiring or ordering miss, fixing only that instance is incomplete. Enumerate the class first, fix all siblings. Example: a "bare `OK` is not a verdict" rule must enumerate all bare verdict values (`OK`, `N/A`, `FINDING`, `not verified`) and wire enforcement for each — not just the called-out one. A "place section X immediately after section Y" rule must enumerate all content currently sitting between X and Y (summary blocks, separator lines, footers) and relocate each — not just remove the one named in the finding. Blast-radius discipline ("enumerate all consumers — verify fix covers every one") applies to rule-additions, not only to code changes. Fixing one instance ships the sibling as the next round's finding.

- **Describe-vs-emit parity (rule prose ↔ implementer surface form)** — The bullets above cover wiring *presence* (is the implementer file in the diff?) and class *enumeration* (did the fix cover every sibling?). They do NOT cover content parity: does the rule's prose description of implementer behavior match what the implementer actually emits? When the rule source describes implementer surface form — "the agent emits X", "templates use Y", "field is named Z", "the gate accepts `### Findings` because agents render that header" — grep the actual implementer files for the described form. If the prose describes a surface the implementer doesn't emit (or vice versa), both files were touched but content drifted between them. Surface as ISSUE — list both the rule claim and the implementer's actual content. **Sweep on first pass, not on bot churn.** A rule-authoring PR that hand-aligns one mismatch and ships will surface every other mismatch as a separate bot finding on subsequent pushes; each fix opens the next drift point. Read the rule source once, enumerate every implementer claim, grep all consumer files in a single pass before the first push.

## Tone

- **Suggestive tone when intent is unknown** — When reviewing code where the author's intent isn't clear, use suggestive language ("worth considering", "you might want to") rather than prescriptive ("add this", "change this"). Reserve directive language for clear standards violations.

## Review Process

- **Read files from the PR branch HEAD, not the patch diff** — `gh pr diff` shows cumulative changes but early hunks may reflect intermediate commits, not the final state. Always `git fetch` the branch and `git show <branch>:<file>` to read the actual current code.

- **De-duplicate against existing PR comments before posting** — Read all inline comments (bot + human) before drafting findings. If a finding is already stated by another reviewer, don't repost it. **Always fetch comments with `{id, author, body}` — never `.body` alone.** Fetching only `.body` concatenates all bodies in sequence with no delimiter; it's trivially misread as one message and has caused misattributed findings (e.g. assuming an author copied a bot's text when they were just sequential outputs).

- **Read each existing comment individually before labeling it stale** — When characterizing pre-existing bot/reviewer comments as outdated, fetch and read each one independently. A blanket "all three reference the old version" claim is usually wrong for at least one comment. State specifically what each comment references and why it's stale or addressed.

- **Check for redundant event triggers** — When a workflow has multiple triggers that can fire for the same real-world action (e.g. `push.tags` + `release: [published]` both fire when a release is created with a new tag), flag the redundancy. With `cancel-in-progress: true`, the second trigger cancels the first mid-run — amplified by any multi-step sequential work added by the PR.

- **Review full files**, not just diffs. Context reveals duplicates, inconsistent patterns, missing imports.

- **Ask whether the change is necessary** — For any new abstraction, new configuration value, new dependency, new permission, or expanded surface area: ask "What breaks if this change is reverted?" If the answer is "nothing currently breaks", flag as SUGGESTION noting that the benefit-vs-complexity trade-off is unclear. This applies to defensive code added "for future use", permissions added "just in case", and config values with no current consumer. The system has additive bias by default — this question is the counterweight.

- **Flag obvious-fact code comments and inline WHY-prose** — A comment that restates what the code does (`# Loop through list`, `# Check if condition`, `# Initialize variable`) is noise. Flag as SUGGESTION for removal. A single-line WHY comment is the accepted inline form; rationale longer than one line belongs in docs (see the multi-line WHY rule above). Beyond single-line WHY, two narrow carveouts stay inline because the comment is contract, not prose: (1) **comments mandated by another rule or by the toolchain** — suppression directives (`# noqa`, `# type: ignore[...]`, `# pragma: no cover`, `# fmt: off`/`# fmt: on`, `# zizmor: ignore[...]`, `# eslint-disable-line`, etc.) and language escape-hatch comments (TS non-null `!` safety notes, Go intentional `_` error discards, Rust `unsafe` blocks); (2) **one-line pointers** that link to a doc entry. Multi-line rationale outside these carveouts: flag as SUGGESTION with a pointer to move the content to a doc.

## Adversarial Pass (mandatory after Pass 2)

Before presenting findings, challenge both what was found and what was missed.

- **Challenge each finding** — For every finding, ask: "Would I bet my reviewer credibility on this?" If not, drop it or downgrade. Unverified observations and "the author should confirm" labels do not exempt a finding from this challenge.

- **Challenge the absence of findings** — Ask: "What did I miss?"
  - Simulate production: would this break under real traffic or real tenant data?
  - Simulate first-time operator: would this confuse someone deploying it for the first time?
  - Simulate state collision: would existing deployed state conflict with this change?
  - Check edge cases: empty values, missing env vars, first-run vs. re-run behavior
  - For scripts that generate artifacts: what input characters break the output format?
  - For modified functions: does the sibling function processing similar data apply the same sanitization?

- **Challenge dismissals** — For every finding flagged by a bot reviewer or another agent that you dropped: would you post your dismissal reasoning publicly to the PR? If no, surface the finding with your reasoning and confidence so the user can override.

This pass is not optional. Every review includes it by default.

## Dismissing Findings (no silent drops)

A finding flagged by a bot reviewer or a reviewer agent is the system telling you something. Dismissing it without process has a documented track record of letting real bugs through.

- **Surface every dismissal with reasoning and confidence** — In the review output, present the dismissed finding with: source, finding text, your verification, conclusion, confidence level. Format: "Bot flagged X. I checked Y and found Z. I think this is a false positive — confidence: low/medium/high. Flagging for your call." The user makes the final dismissal call.
- **Description-based dismissals are forbidden** — "The PR description says a prior PR fixed this" is not evidence. Fetch the actual file in the referenced repo (`gh api repos/{org}/{repo}/contents/{path}?ref=main`) and verify the claim against the merged code. If unable to verify, surface the finding with that limitation noted — do NOT drop it.
- **Cross-repo claims require cross-repo verification** — When a finding's truth depends on code in another repo, read that file before dismissal. A review worktree only contains the PR's own repo; cross-repo behavior is structurally invisible unless fetched explicitly.
- **Confidence levels** — High: contradicted by code read end-to-end. Medium: seems wrong but not every path traced. Low: hunch only. Medium and low ALWAYS surface to the user with the dismissal reasoning visible.
- **A finding wrong about mechanism can still be right in impact** — Before dismissing on "the stated mechanism is factually incorrect", check whether any CI gate (security scanner, lint, branch ruleset, required check) enforces the *outcome* the finding warns about. Dismissal requires refuting the impact, not just the explanation.
- **Dropped findings are logged, not invisible** — Even when dropped with high confidence, the review output includes a "Findings dropped after verification" section listing what was dropped and why, so the user can override.

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
