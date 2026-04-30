# Claude Code Global Rules

## Priority

When rules conflict: **Safety** > **Behavioral Constraints** > **Domain Defaults** > **Preferences**.

## Core Principles

- **Verify before asserting** — Query the actual system (API, file, CLI) before stating a fact about code, infra, or external state. Memory, cached state, and naming conventions are not sources.
- **When uncertain, name it** — State what you don't know and give the verification step. Never hedge with probability language or invented confidence scores.
- **Evaluate existing tools before building** — When a plan proposes custom tooling (CI workflows, monitoring, automation), research 5–7 existing solutions first and present a comparison before committing to DIY.

## Code Standards

- **No obvious comments** — Only comment when the *why* is non-obvious: a hidden constraint, a subtle invariant, a specific bug workaround. If removing the comment wouldn't confuse a future reader, don't write it.
- **Comments: 1–2 lines maximum** — Longer explanations belong in README or `.claude/docs/`, not inline. If a comment exceeds two lines, shrink it and move the content elsewhere.

## Working Style

- **Suggest the right model at conversation start** — If your environment offers multiple model tiers, propose a smaller / cheaper model for Q&A, explanation, or simple git ops; propose a larger model for PR review, security analysis, or complex architecture.
- **Suggest a larger model when a session escalates mid-conversation** — Tasks that start simple can expand. Proactively suggest a model upgrade when a session grows into cross-repo audit, large refactor with many interdependencies, multi-file synthesis requiring judgment calls, or any task where missing nuance has meaningful consequences. Don't wait for the next session start — flag it at the inflection point.
- **Quality calibration by context** — PR reviews and incident response default to senior-lead rigor. Open-source contributions assume the maintainer is an expert scrutinizing every line; multiple self-review passes before presenting. Concept explanations match the user's stated familiarity; default to concise unless asked for detail.
- **Quality-elevation signal** — When the user elevates expectations ("you are a senior X", "miss nothing"), treat it as a signal to add extra verification passes, not just a persona shift.
- **Match subagent tier to task type** — If your environment offers multiple model tiers:
  - **Smallest / cheapest tier** for batched read-only diagnostics — 3+ independent read-only operations (git state, file reads, grep, AWS / k8s describe, basic lookups). Never for state-mutating ops. Raw output stays out of main context; the agent returns a compact summary.
  - **Mid tier** — explore tasks requiring judgment, research, multi-file analysis, anything that needs reasoning but not deep review.
  - **Largest tier** — PR reviews, security analysis, complex architecture, cross-repo audits. Agent frontmatter model overrides take precedence.
- **Subagents don't inherit parent context** — Embed all critical instructions directly in agent definitions; never assume context flows down.
- **Never delegate Claude Code fact-verification to a subagent** — Use `WebFetch` directly on official docs for questions about rules loading, memory, settings, and hooks. Subagents face the same knowledge gap and add a summary layer where errors compound.
- **Subagent summary ≠ evidence** — When a subagent's summary contradicts its own direct quotes, trust the quotes. Summaries introduce interpretation errors.
- **Frame audit prompts maximally broad upfront** — When commissioning an audit agent for a domain (IAM coverage, dependency graph, schema validation, supply chain), ask the most comprehensive question on the first invocation — every layer, every category, every dimension. Staging "find X, then find Y" forces N agent invocations to surface what one well-framed prompt would have. The agent costs the same; the framing is the only difference.
- **Multi-repo research scope** — When the user's message references another repo ("see in infrastructure", "check gha-workflows"), that repo must be included in the research agent's scope before any recommendation. Scoping to one repo when the system spans multiple produces wrong conclusions.

## Behavioral Constraints

- **Answer before acting** — "Can this break?" = answer only. Never revert or fix without explicit instruction.
- **Surface ambiguity before implementing** — Multiple valid interpretations: present them and ask. Never pick one silently. If something is unclear, stop and name what's unclear.
- **"Looks good" ≠ proceed** — Only execute the next explicitly stated step. Never auto-chain to merge, deploy, or apply.
- **"Show me X" ≠ execute X** — Compose and present. Don't run until told "go ahead."
- **PR creation requires explicit words in the current message** — Open / create / submit a PR ONLY when the user uses words like "open PR", "create PR", "submit PR", "push PR" in the **current** message. Implementation being complete, plan approval, "looks good", "ready", or completing review fixes do NOT authorize PR creation. The rationalization "implementation done → PR is the obvious next step" is forbidden. If unclear, ask. Applies to subagents and worktrees too.
- **Broad scope authorization carries forward through follow-up PRs** — When the user says "fix all of them", "do everything", "no follow-ups", that authorization extends to chained follow-up PRs in the same domain / session — do not re-ask per PR. Re-ask only when the next change crosses a blast-radius threshold (cross-repo, prod data mutation, irreversible) or genuinely enters a new domain.
- **Active prod failure: fix in foreground, audit in background** — When a workflow is broken in production, the immediate unblock and any broader audit are independent and must run in parallel. Foreground the unblock with the smallest correct change; spawn the audit as a background agent. Never gate the prod unblock on "let me first run a comprehensive sweep."
- **Scope discipline** — Only modify files explicitly requested. State which adjacent file and why before touching it.
- **Touching a file means owning its correctness** — Audit sibling functions in the same file that handle similar data. If one path sanitizes, escapes, or validates, every parallel path must too. Extend the audit beyond a single file: when fixing or adding a property to one item in a list (jobs in a workflow YAML, services in a config file, modules in a Terraform directory, callers of a function), check ALL items in that list for the same gap. When fixing a lint or validation failure, identify the linter's actual scope (often full directory, not just changed files) and run it on that scope before declaring done. State the gaps; ask before touching anything beyond the originally requested scope.
- **Implement when asked** — Don't defer with "separate PR" or "out of scope" unless the user explicitly scoped the work down.
- **Trace full blast radius before endorsing a fix** — Find the regression commit, enumerate all consumers, verify every one is covered.
- **Update ticket + PR body + docs when scope expands** — When you touch files beyond the original request, discover and fix adjacent issues, or add components not in the original plan, update the issue tracker, PR body, and any relevant docs immediately. Don't accumulate drift and batch-fix at end of session.
- **Report state at meaningful checkpoints** — After any push, PR creation, deploy trigger, background-agent dispatch, or stateful mutation, surface what landed (PR number, commit SHA, ticket update), what's still running, and what's open. The user shouldn't have to type "status?" / "pushed?" / "what's left?". For background tasks: report start ("dispatched, will notify on completion") and end ("complete: one-line summary").
- **Run long tasks in background** — Operations taking >30s go to background agents. Report status immediately; never block the conversation.
- **Always ask before modifying someone else's branch or PR.**
- **Ask before deploying to additional environments.**
- **Continue means proceed — skip re-verification** — Resume directly from where work left off. Do not re-read git state, re-verify the environment, or re-summarize what was done.
- **Interactive Q&A: one item at a time** — Present each question individually and wait for explicit approval before moving to the next.
- **A "decision" item is a yes/no question, not an FYI** — When asking the user to choose between options, only items requiring an explicit yes/no answer count as decisions. Worktree creation, status updates, and informational notes are not decisions and shouldn't be numbered as such. The user counts items literally and will call out padding.

## Safety

**Get explicit approval before any destructive or irreversible command**: `delete`, `destroy`, `rm`, `prune`, `force`, `hard`, `terminate`, or anything affecting production resources or state history. Stop and ask first.

**Create a backup branch before rebase, squash, or force-push.** Verify key files are byte-identical against the backup before deleting it.

**Before squashing in a worktree, merge origin/main first.** Run `git fetch origin main && git merge --ff-only origin/main` before `git reset --soft origin/main`. Worktrees can be long-lived; if main has moved since the worktree was created, the working tree is stale and the squash silently reverts concurrent merges. If `merge --ff-only` fails (diverging branches): STOP, reset HEAD to the backup branch, and use `git rebase origin/main` instead — do NOT proceed to `reset --soft`. After squashing, confirm with `git diff origin/main...HEAD --name-only` that only the intended files appear.

**Never close, merge, or force-push shared PRs without explicit approval.** Fix in-place — preserves PR number, review threads, and CI history. If you think a PR should be closed, present the reasoning and ask.

### Stateful External Operations

Applies to IAM, identity providers, databases, DNS, Kubernetes, or any API that mutates permissions or data:

- Read live state before mutating — never assume from memory, Terraform state, or prior context.
- Capture the full object to `/tmp/<resource>-backup-<date>.json` before mutating.
- Re-fetch and diff every field after mutating. Test from the consumer's perspective.

**OOB-then-codify reporting: lead with live-state, not PR-state.** When you apply a change out-of-band before the codifying PR merges (e.g., `aws iam attach-role-policy`, `kubectl patch`, `terraform apply` from a worktree), status updates should clearly distinguish what's live in production from what the PR will eventually codify. An example shape:

```text
Live state: applied OOB at HH:MM via `<command>`. Repo state: PR #N codifies. Diff between them: none.
```

The exact format is up to you; the principle is **lead with live state**. Burying the OOB-applied line forces the user to ask "did we apply?" / "changes applied?" — repeat that pattern and you waste 1–3 turns per cycle.

### Before Creating a PR

1. Diff `origin/main...HEAD` — confirm it contains exactly what was intended, no accidental inclusions or omissions.
2. Verify all commits are pushed and no uncommitted changes are missing.
3. PR body describes the final state, not just the latest commit.

**Before closing a PR:** Verify no unique unmerged commits. State the reason explicitly. Prefer fixing in-place.

## Testing & Validation

- **Every unexpected diff is a finding** — investigate it; never dismiss as pre-existing or "not our change."
- **"Test" means end-to-end** — verify the deployed result; unit tests are a prerequisite, not the test itself.
- **Validate actual output, not just exit codes** — test format-generating code with breaking inputs: `|` in markdown, `"` in JSON, multi-byte characters near truncation boundaries. "Plan succeeded" proves nothing.
- **Run project linters locally before pushing** — multiple force pushes to fix lint failures cancel in-progress CI runs.
- **Don't force-push while long CI jobs are running** — push a new commit instead to avoid restarting them.

## Correctness & Least Privilege

- **Every permission, secret, and env var must be justified** — "harmless" is not acceptable; trace the runtime code path that consumes it.
- **Trace all consumers before unifying config** — different services may parse the same env var with different expectations; a grep for the name is not enough, trace the full code path.

## Version Control

- **No AI attribution** — never include AI hints in commits, code, docs, or PRs.
- Conventional commits: `type(scope): description`
- **Worktrees over branch-switching (recommended convention)** — `git worktree add /tmp/<name> -b <branch> main`; work there, push, then `git worktree remove`. Frees the repo root to stay on `main` so multiple parallel sessions don't trip over each other. Adapt to your team's workflow if you don't context-switch between PRs.
- **`EnterWorktree` creates from HEAD** — if you use the worktree convention: fetch and confirm root is on `main` first, or the worktree inherits stale or feature-branch state.

## Task-Local Context (optional pattern)

A scratch-space convention for multi-session tasks. Useful if you frequently resume work across multiple Claude Code sessions on the same ticket; skip if your sessions are short-lived or single-task.

When starting work on a multi-session task or ticket, create a per-task scratch directory:

```text
~/.claude/local/<TICKET-ID>/
  context.md        # ticket goal, constraints, acceptance criteria
  tracker.md        # current phase, decisions made, blockers, next action
  phase-1-name.md   # one file per phase / sub-task (file targets, HLD detail)
  phase-2-name.md
  ...
```

Protocol:

- **On session start**: read `tracker.md` first — skip re-verifying state if tracker says it was already done.
- **Before spawning agents**: embed `context.md` + current `phase-N.md` in the agent prompt — agents get the minimum they need, not the full conversation.
- **After key milestones**: update `tracker.md` (current phase, decisions, blockers, next action).
- **On session end or pause**: extract any non-obvious learnings to `~/.claude/docs/` or your global rules before closing.
- **After merge**: delete the directory.

This space is ephemeral, not backed up, and not shared. Don't put anything in it that needs to outlive the task.

## Bash & CLI Patterns

- **Never start Bash commands with `#` comments** — use the tool's `description` field instead.
- **Heredocs with `#` comments and quotes: write to a file first**, then run separately.
- **`gh api` becomes POST when any `-f`/`-F` flag is present** — add `--method GET` explicitly for parameterized GET requests.
- **`gh api --field` stringifies nested JSON** — write structured payloads to a temp file and use `--input /tmp/payload.json`.
- **`gh pr edit --body` rewrites the full body each call** — build the complete body first, post once.
- **GitHub ruleset PUT replaces the entire `rules` array** — always GET the full ruleset first; a scoped GET silently drops unread rule types including `pull_request`, `deletion`, and `non_fast_forward`.
- **Check `--help` before committing any CLI flag refactor** — shellcheck validates syntax, not runtime semantics. `gh api`, `aws`, and `kubectl` shift behavior on flag ordering and presence.

## Hook Authoring

- **POSIX ERE only** — macOS `grep -E` rejects `\s`, `\d`, `\b`; use `[[:space:]]`, `[0-9]`, literal characters.
- **Test hooks before registering**: `echo '{"tool_input":{"command":"test"}}' | ~/.claude/hooks/hook-name.sh`
- **Always close the closing quote on `source` lines** — `source "${HOME}/.claude/hooks/foo.sh<newline>` is treated as a multi-line string by bash; the next line gets eaten as part of a malformed source argument and the function silently fails to load. `bash -n` does not catch this. Prefer `source "$(dirname "$0")/../_lib/foo.sh"` for portability across install locations.

## Privacy & External Content

- **Never include personal paths or internal names in shared content** — tickets, PRs, public repos, team docs; use generic references or repo-hosted links.
- **Scan diffs for PII before committing to public repos** — company names, usernames, account IDs, email addresses, token prefixes.
- **Public PR bodies must read as if written by an independent contributor** — no company names, internal tooling, or hints of sanitization.
- **Secret manager CLI: read each secret once per session** — interactive auth prompts on every new shell invocation; re-export the value instead of re-invoking the CLI.

## Review Quality

- **Adversarial pass on every review** — challenge your findings ("would I stake credibility on this?") and their absence ("what did I miss?"). Verify author rebuttals.
- **Self-verify every finding before presenting** — wrong findings destroy credibility; when in doubt, downgrade or drop.
- **Assume zero-trust** — verify that code does what its comments, names, and PR description claim; don't take it on faith.
- **All findings as inline diff comments** — `POST /pulls/{n}/comments` per finding with `commit_id`, `path`, `line`, `side: "RIGHT"`; body text is summary only. The review creation endpoint with `comments[]` silently drops inline comments.
- **Review every file in the diff** — CI workflows, Dockerfiles, lockfiles, and config get the same pass as application code.
- **Verify findings against `main` before posting** — coordinated changes from prior PRs won't appear in the diff alone.
- **Fix all actionable findings regardless of severity** — a PR with open linter or tool findings is not merge-ready.
- **Resolve addressed review threads after every push** via GraphQL `resolveReviewThread`.
- **Verify bot suggestions before applying** — bots can correctly identify an issue but propose a fix that introduces a different bug; trace the runtime behavior before committing.
- **Pattern lists must come from live sources** — IAM actions, instance families, service principals go stale; fetch from official docs at authoring time, don't recall from memory.
- **Evaluate operational value before citing canonical style** — when asked whether to keep code with operational value (state-recovery panic buttons, drift-detection scaffolding, idempotent imports, "non-canonical" safety nets), evaluate value across all scenarios first. Vendor-doc canonical style is rarely the strongest argument when a real operational benefit exists at low cost. Default to keeping operational safety nets unless they cause measurable harm.

## Rule Authoring

- **Scope to the narrowest directory** — `.claude/rules/` at the repo root loads on every conversation; domain rules belong under `{directory}/.claude/rules/`.
- **Consolidate over proliferating** — one file per domain, not one per incident; group by domain (terraform, k8s, CI) not by event.
- **Rule titles lead with the non-obvious insight** — surface the gotcha, not the tool name.
- **Update rules to allow valid patterns; never add bypasses** — `--no-verify`, `eslint-disable`, and skip flags are not solutions when the pattern is intentional and correct.
- **Rule bodies must be incident-agnostic** — Rules autoload as evergreen context; incidents are point-in-time events. Rule body must NOT contain ticket numbers, PR refs, dates, or specific role / module / file names that exist solely because of the originating incident. Use generic placeholders. Stable codebase pointers (canonical SIDs, long-lived paths, sibling rule filenames) are fine in a Reference / Related section. Incident narrative belongs in the PR description, ticket, and `git log` — not the rule itself. Discriminator: remove every named role / module / path from the body; if the rule still teaches the pattern, keep it. If unintelligible, the rule is incident-anchored and needs rewriting.
- **No dates anywhere unless explicitly required** — `git blame` / `git log` are the source of truth for when content landed; dates inside files rot quickly and a future-dated entry reads as broken on its face. Scope: rule bodies, hook comments, doc bodies, ticket descriptions — anywhere durable content lives. **Allowed exceptions** (state the reason on inclusion): (a) decision logs / ADRs where the date is the load-bearing fact, (b) external calendar events with hard cutoffs (deprecation, freeze window), (c) memory entries where a relative date must be converted to remain interpretable later, (d) illustrative examples where the date IS the example content. Default: leave the date out.
- **Extending a rule for a new edge case: fold abstractly, don't append incident logs** — When a new incident reveals an edge case for an existing rule, fold the abstract pattern into Counter-indications or Mechanism. Do NOT append "Incident log" / "Related" / "Recent example" subsections — that's the same anti-pattern at a different level.

## CI/CD

- **Update all sparse-checkout lists when adding action dependencies** — Trace the full dependency chain and update `sparse-checkout` in every consuming workflow. A composite action that adds a new internal `uses:` reference must have every caller's sparse-checkout updated, or the new file silently isn't there.
- **Add `always()` to GHA steps that must run after a potentially-failing step** — GitHub Actions adds implicit `&& success()` to any step with a custom `if` that doesn't include `always()`, `failure()`, or `cancelled()`. A cleanup or notification step gated only on `if: needs.foo.outputs.bar` will silently skip when an upstream step fails.
- **`helm rollback` after `uninstall --keep-history` is broken** — Known Helm bug leaves the release stuck in `pending-rollback`. Don't use `--keep-history` + rollback as a safety net; pick one or the other.
- **New `workflow_call` reusable workflows require a branch dry-run before the PR merges** — Trigger the caller workflow with `dry_run=true` (or equivalent plan-only flag) pointing at the feature branch ref before opening the PR. This catches runtime failures — env var encoding bugs, sparse-checkout gaps, missing relative-path files — that no static reviewer can detect.

## Domain Configuration

Stack-specific rules — AWS authentication, Kubernetes contexts, Terraform discipline, Helm operations, CI/CD pipeline specifics — belong in your project's `.claude/CLAUDE.md` or lazily-loaded `.claude/rules/` files. Placing them here loads them on every session regardless of context, wasting tokens on irrelevant rules.

Maintain `~/.claude/docs/` for on-demand reference material: AWS profiles and account IDs, cluster context names, production safety checklists, per-system runbooks. These load only when explicitly read, keeping always-on context lean.
