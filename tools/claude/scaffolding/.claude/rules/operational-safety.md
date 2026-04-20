# Operational Safety Rules

- **Re-verify state after context continuation** — After any context continuation or session handoff, re-read actual files for: current git branch, terraform workspace, image tag, and target workflow. Never rely solely on continuation summaries for operational values.

- **Checkpoint deep sessions proactively** — When a session is deep (50+ tool calls, multiple modules), offer a checkpoint summary: current branch, what's done, what remains, and any open decisions.

- **Plan mode rejections mean the plan isn't ready** — When ExitPlanMode is rejected, ask what's missing. Don't try to exit again without addressing feedback. Present plans incrementally.

- **Enumerate before destructive operations** — When asked to "remove" or "clean up," produce an explicit numbered list of exactly which resources will be affected. Get per-item or per-batch confirmation. Never infer scope from broad terms.

- **Read before editing — no parallel edits without reads** — Never issue an Edit call for a file not read in the current turn. When editing multiple files, read them all first, then edit. After context continuations, re-read before editing.

- **Cross-reference all variants before copying** — When duplicating or adapting files that exist in multiple variants (e.g., staging/production, sibling modules), diff all available variants first. A difference between variants is not automatically a bug — verify whether it has any effect by tracing how the value is consumed.

- **Fix diagnostics immediately — never rationalize them away** — When IDE diagnostics or linter warnings appear after a change, fix them in the same session. Do not classify warnings as "minor" or "style-only" to avoid fixing them. Every diagnostic is a finding.

- **Failure analysis: cheapest diagnostic first, no premature fixes** — When investigating a failure: (1) classify the error signature (timeout = transient, 403 = access, connection refused = network); (2) if transient, recommend a re-run before deep investigation; (3) present a diagnosis and get confirmation before editing files; (4) configuration differences found during investigation are findings to report, not automatic root causes — correlation is not causation.

- **Stateful Operations Protocol for external system mutations** — Any action that modifies state in an external system (identity providers, IAM, databases, Kubernetes, DNS, APIs) requires: (1) state your hypothesis explicitly, (2) query the live system to verify — never rely on assumptions, (3) capture baseline before acting, (4) identify blast radius, (5) execute the smallest possible change, (6) verify from BOTH admin API and consumer/end-user perspective, (7) spot-check entities you did NOT intend to change. Rollback is itself a stateful operation — re-run this protocol for rollback steps. The `stateful-op-reminder` hook enforces this as a model-facing nudge. See `shared/principles/operational-safety-patterns.md` for the full 17-step protocol.

- **PR operations are shared state** — Before creating a PR: review the actual diff (not what you think is in it), verify all commits are pushed, verify no uncommitted changes are missing, ensure the PR body describes the final state. Before closing a PR: read it fully, check for open review threads, confirm the reason, verify no unmerged work will be lost. Prefer fixing branches in-place over close+reopen.
