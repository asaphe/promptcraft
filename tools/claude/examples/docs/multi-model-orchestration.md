# Multi-Model Orchestration (Claude plans, other models execute)

The operating model: **Claude is the planner / orchestrator / judge; cheaper or specialized executor models do the bulk work.** Claude decomposes work into verifiable tasks, dispatches each to the cheapest capable executor, and judges the result. Synthesis, architecture, security, and review are never delegated — the judgment *is* the work.

This pattern assumes two representative executors reachable from the shell: a **cheap/large-context model** (referred to here as the *bulk executor*) and a **stronger code-heavy model** (the *complex executor*). Substitute whichever CLIs you have.

## Cost-tier routing

Route each task to the cheapest executor that can do it correctly:

| Tier | Role | Gets the work when… |
|---|---|---|
| **Plan / judge** | **Claude** | Decomposition, dispatch, judging executor output, architecture, security, PR review, synthesis. Never delegated. |
| **Cheap / high-volume / large-context** | **Bulk executor** | Low-risk bulk codemods, repo-wide read+summarize, doc/boilerplate generation, first-pass drafts, large-file analysis (large context window). |
| **Complex / code-heavy** | **Complex executor** | Non-trivial refactors, test suites, multi-file logic changes — or **escalation** when the bulk executor's draft fails Claude's review. |

**Escalation path:** bulk draft → Claude judges → if it fails acceptance, escalate the *same* task to the complex executor → Claude re-judges. Difficulty heuristic for initial tier = risk × logic-complexity × file-count.

**On a flat-rate subscription, the currency being saved is context + rate-limit quota, not dollars.** When Claude Code runs on a flat-rate plan there is no per-token bill to reduce, so the routing calculus favors offloading anything that would pull large content into Claude's context *even when Claude could do it inline* — the cost avoided is quota and context budget.

- **Large reads default to the bulk executor.** Reading a large file, a long command/log output, or a wide grep result that's only needed *summarized or judged* (not edited) goes to the cheap large-context model, which returns the distilled answer on its own quota. This is the single biggest avoidable burn — offload it by default, don't reason over the raw dump inline.
- **Still never micro-dispatch a small reasoning task.** A one-shot dispatch carries fixed executor system-prompt overhead (often ~10k+ input tokens); for a small task Claude could reason through inline, that overhead isn't worth it. Batch work into one dispatch. This anti-micro-dispatch rule scopes to *small reasoning* — it does not override "large reads default to the bulk executor."

## Dispatching a CLI executor from Claude Code

Claude Code's Bash tool starts a **fresh shell per call** and `export` does not persist across calls. So load any required credential/env and dispatch in the **same** call:

```bash
# Load auth (source your key-loading function or export the key), then dispatch in one call:
source <your-env-setup> && <bulk-executor-cli> -p "<scoped objective>" --output-format json
```

- Prefer a CLI installed on a **stable PATH** (e.g. a system package manager) over a version-manager-global install — lazy-loaded version managers (nvm and similar) aren't initialized in non-interactive shells, so their global bins are often off PATH.
- If the executor requires a "trusted workspace" flag for headless runs, pass it per-call (many CLIs fail with a "not running in a trusted directory" error otherwise).

**Output-parsing gotcha:** many CLIs write startup/warning lines to stdout *before* the JSON payload. Extract from the first `{` before piping to `jq`/`python` — e.g. `… | sed -n '/^{/,$p' | jq -r '.response'`. Read the result field for the answer and the token/usage stats for cost accounting. Escalate to a heavier model per call with the CLI's model flag only when the default tier fails review.

## Dispatching a workspace-aware executor

Some executors read the working tree directly and run synchronously in the current workspace:

```bash
<complex-executor-cli> exec "<scoped objective>" </dev/null
```

- **Redirect stdin (`</dev/null`)** if the CLI otherwise blocks reading from stdin; pass the objective as the positional arg.
- Tune per call with the CLI's reasoning-effort / config-override flags; reserve the highest effort for genuinely hard synthesis.
- Scoped and token-minimal: precise objective, explicit file paths, narrow acceptance criteria. The executor reads the worktree — **point, don't copy** file contents or diffs into the prompt. One dispatch = one verifiable deliverable; Claude judges the result before accepting.

## Dispatch hygiene (all executors)

- **Point, don't copy** — executors read the repo/worktree; never paste file contents, diffs, or conversation history into the dispatch prompt.
- **One dispatch = one verifiable deliverable** with explicit acceptance criteria Claude can check.
- **Isolate parallel mutating work** in separate git worktrees so executors don't collide.
- **Claude judges every result** against the acceptance criteria before accepting — an executor's "done" is a claim, not proof.
