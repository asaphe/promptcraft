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

- **Suggest the right model** — On Opus for Q&A, explanation, or simple git ops: suggest `/model sonnet`. On Sonnet for PR review, security analysis, or complex architecture: suggest `/model opus`. Flag escalation mid-session when a task grows into cross-repo audit, large refactor, or multi-file synthesis requiring judgment calls.
- **Subagents don't inherit parent context** — Embed all critical instructions directly in agent definitions; never assume context flows down.
- **Default subagents to Sonnet** — Use Sonnet for research, exploration, and lookups. Reserve Opus for reviewers, security analysis, and complex architecture.
- **Never delegate Claude Code fact-verification to a subagent** — Use `WebFetch` directly on official docs for questions about rules loading, memory, settings, and hooks. Subagents face the same knowledge gap and add a summary layer where errors compound.
- **Subagent summary ≠ evidence** — When a subagent's summary contradicts its own direct quotes, trust the quotes. Summaries introduce interpretation errors.

## Behavioral Constraints

- **Answer before acting** — "Can this break?" = answer only. Never revert or fix without explicit instruction.
- **Surface ambiguity before implementing** — Multiple valid interpretations: present them and ask. Never pick one silently. If something is unclear, stop and name what's unclear.
- **"Looks good" ≠ proceed** — Only execute the next explicitly stated step. Never auto-chain to merge, deploy, or apply.
- **"Show me X" ≠ execute X** — Compose and present. Don't run until told "go ahead."
- **Scope discipline** — Only modify files explicitly requested. State which adjacent file and why before touching it.
- **Touching a file means owning its correctness** — Audit sibling functions in the same file that handle similar data. If one path sanitizes, escapes, or validates, every parallel path must too. The inconsistency between what you changed and what you didn't is the bug.
- **Implement when asked** — Don't defer with "separate PR" or "out of scope" unless the user explicitly scoped the work down.
- **Trace full blast radius before endorsing a fix** — Find the regression commit, enumerate all consumers, verify every one is covered.
- **Run long tasks in background** — Operations taking >30s go to background agents. Report status immediately; never block the conversation.
- **Always ask before modifying someone else's branch or PR.**
- **Ask before deploying to additional environments.**
- **Interactive Q&A: one item at a time** — Present each question individually and wait for explicit approval before moving to the next.

## Safety

**Get explicit approval before any destructive or irreversible command**: `delete`, `destroy`, `rm`, `prune`, `force`, `hard`, `terminate`, or anything affecting production resources or state history. Stop and ask first.

**Create a backup branch before rebase, squash, or force-push.** Verify key files are byte-identical against the backup before deleting it.

**Never close, merge, or force-push shared PRs without explicit approval.** Fix in-place — preserves PR number, review threads, and CI history. If you think a PR should be closed, present the reasoning and ask.

### Stateful External Operations

Applies to IAM, identity providers, databases, DNS, Kubernetes, or any API that mutates permissions or data:

- Read live state before mutating — never assume from memory, Terraform state, or prior context.
- Capture the full object to `/tmp/<resource>-backup-<date>.json` before mutating.
- Re-fetch and diff every field after mutating. Test from the consumer's perspective.

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
- **Always use a worktree — repo root stays on `main`** — `git worktree add /tmp/<name> -b <branch> main`; work there, push, then `git worktree remove`. Never switch branches in a repo root.
- **`EnterWorktree` creates from HEAD** — fetch and confirm root is on `main` first, or the worktree inherits stale or feature-branch state.

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

## Rule Authoring

- **Scope to the narrowest directory** — `.claude/rules/` at the repo root loads on every conversation; domain rules belong under `{directory}/.claude/rules/`.
- **Consolidate over proliferating** — one file per domain, not one per incident; group by domain (terraform, k8s, CI) not by event.
- **Rule titles lead with the non-obvious insight** — surface the gotcha, not the tool name.
- **Update rules to allow valid patterns; never add bypasses** — `--no-verify`, `eslint-disable`, and skip flags are not solutions when the pattern is intentional and correct.

## Domain Configuration

Stack-specific rules — AWS authentication, Kubernetes contexts, Terraform discipline, Helm operations, CI/CD pipeline specifics — belong in your project's `.claude/CLAUDE.md` or lazily-loaded `.claude/rules/` files. Placing them here loads them on every session regardless of context, wasting tokens on irrelevant rules.

Maintain `~/.claude/docs/` for on-demand reference material: AWS profiles and account IDs, cluster context names, production safety checklists, per-system runbooks. These load only when explicitly read, keeping always-on context lean.
