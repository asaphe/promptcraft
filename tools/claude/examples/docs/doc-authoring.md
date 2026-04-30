# Doc, Rule & Agent Authoring

## Writing rules and agent instructions

- **Lead with positive guidance** — "Always X" over "Never Y". Reserve NEVER for genuinely dangerous operations (state mutations, force-push, production deploys). Positive framing is followed more reliably under context pressure.
- **Capture the principle, not just the incident** — A rule should prevent the entire class of mistake, not only the exact scenario that prompted it. Ask: "Would this also prevent the next variant?"
- **Each instruction must earn its context budget** — Would removing this rule cause Claude to make mistakes? If not, cut it. ~150–200 always-loaded instructions is the reliable limit.
- **Concrete over abstract** — "Check for ticket references in section titles" beats "ensure no stale data." Include the why so edge cases can be judged.
- **Read `.claude/docs/doc-quality-checklist.md` before submitting any `.claude/` config change** — staleness scan, content accuracy, instruction quality checks.

## Reviewing rules and agent config

When reviewing PRs that add or modify `.claude/rules/`, `.claude/agents/`, or `CLAUDE.md`, check against the full quality checklist in `.claude/docs/doc-quality-checklist.md`. Key checks that are commonly missed:

- **Instruction budget** — Count total always-loaded instructions (rule files + CLAUDE.md). Budget is ~150; flag when approaching ~140.
- **Progressive disclosure** — Domain-specific knowledge belongs in on-demand docs (`.claude/docs/`), not always-loaded rules. A rule that only matters when working on CI/CD wastes tokens in every other conversation.
- **Right altitude** — Would this rule prevent the next variant of the problem, or only the exact incident? Too specific = bypassed by the next variant. Too vague = no actionable guidance.
- **Positive framing** — "Verify X before Y" over "Don't assume X". Positive guidance is followed more reliably under context pressure.

## Writing docs

- **No temporal references in persistent docs** — Ticket IDs, dates, "as of today", "currently", and "recently" become stale. Use `git log` / `git blame` to trace origins.
- **No negative repo declarations** — "There is no X here" goes stale the moment anyone adds X, with no reminder to update the doc. Describe what IS present; let readers discover what isn't.
- **Descriptions must reflect deployed state, not default behavior** — A reader will assume the doc describes reality, not vendor defaults.
- **Prefer pointers over copies** — Reference authoritative sources by path rather than duplicating tables or lists that will drift. Mark the authoritative source when duplication is unavoidable.
- **Verify every assertion is still true** — Re-read each factual claim against current code before committing. Docs written during implementation often contain interim state superseded by later commits.
