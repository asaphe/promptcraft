# Examples — Claude Code Configuration

Reference examples for `~/.claude/` and project-level `.claude/` configurations: agents, skills, hooks, rules, docs, scripts. Each example has been refined through daily use; company-specific details have been replaced with placeholders.

Several examples that used to live here now ship as maintained Claude Code plugins — intent routing, learning capture, the 1Password/Secrets Manager guards, and the PR review and finalize skills. [`RETIRED.md`](RETIRED.md) maps each old path to its replacement.

## Directory Structure

The four copy-ready routes are declared in [ADOPTION.md](../../../ADOPTION.md). Everything else is browse/adapt material with its own dependencies and activation steps.

### `agents/`

Specialist agent definitions — design agents (architecture, implementation planning), operational agents (deployment, Terraform, K8s troubleshooting, Karpenter, cheap-tier read-only batching) and review agents (security, DevOps, bash, Python, Datadog, ClickHouse, agent-config, general code). Each agent has a focused domain, clear boundaries, and explicit deferral rules. See `docs/agent-roster.md` for the routing table, kept in sync with disk by hand (the generator script targets an adopter's `.claude/` layout, not this repo's).

### `config/`

- **[global-CLAUDE.md](config/global-CLAUDE.md)** — Standalone, stack-neutral baseline with no companion dependency. Start with the guarded [basic recipe](../../../ADOPTION.md#standalone-global-baseline).
- **[global-CLAUDE-advanced.md](config/global-CLAUDE-advanced.md)** — Reference-only, opinionated author profile; adapt selected sections in the source layout rather than installing it wholesale.
- Annotated `settings.json` excerpts showing two key patterns:
  - **`settings-permissions.jsonc`** — Permission allowlists using Bash wildcards, MCP tool namespaces, WebFetch domain restrictions, and Skill permissions.
  - **`settings-hooks.jsonc`** — Hook configuration for PreToolUse command rewriting and statusline display.

### `profiles/`

[operations.md](profiles/operations.md) is an optional project-only profile for stateful infrastructure work. Use its guarded recipe after choosing a project; review overlap with the infrastructure scaffold.

### `docs/`

Supporting documentation referenced by agents and skills:

- **PR review kernel** — `pr-review-rules.md`, `pr-review-verification.md`, `pr-review-posting.md`, `pr-review-cleanup.md`, `comment-resolution-procedure.md`, `pr-review-policy.md`
- **Routing** — `agent-roster.md`, `skill-inventory.md`
- **Operational refs** — `production-safety-protocol.md`, `arc-runners-topology.md`, `aws-client-vpn-ops.md`, `network-policies-audit.md`, `eks-and-vpc-gotchas.md`
- **Terraform** — `terraform-module-anatomy.md`, `terraform-state-moves.md`
- **Datadog** — `datadog-pup.md`, `datadog-dashboard-codification.md`
- **Bash & CLI** — `bash-patterns.md`, `cli-gotchas.md`, `composite-action-spec.md`, `gha-reusable-workflow-patterns.md`
- **Git** — `git-worktree-and-squash-safety.md` (worktree pre-flight, restacking after a squash-merge, the squash protocol, and the predicate a force-push auto-allow actually needs)
- **Testing** — `testing-validation.md` (what has to be true before "done": diagnosis, non-vacuous verification, CI verdicts that survive a correct API read)
- **Consent & capability gating** — `batch-approval-grants.md` (one prompt for a known-size set of identical guarded calls, and the worked refusal of a case that looked batchable)
- **Claude Code internals** — `claude-code-plugin-gotchas.md` (the process registry: why an updated plugin agent can serve stale content with no error)
- **Diagrams** — `drawio-authoring.md`
- **Doc / authoring** — `doc-authoring.md`, `doc-quality-checklist.md`
- **Codification templates** — `secret-naming-template.md`, `1password-caching.md`
- **Orchestration mechanics** — `workflow-scripting.md` (deterministic multi-agent workflow scripting: pipeline vs. barrier, structured returns, budget-scaled loops), `self-paced-loops.md` (dynamic wakeup-delay selection for open-ended recurring tasks), `deferred-tool-loading.md` (name-only tool deferral to cut standing schema-token cost)

### `hooks/`

- **`_lib/`** — Shared utilities sourced by hooks: `strip-cmd.sh` + `strip-quoted-args.pl` (blank heredoc, `-m` and quoted-argument bodies so patterns match the command surface), `split-cmd-segments.pl` (split command segments, tested `$()` nesting, and simple backticks so a flag test runs against the command that owns it), `resolve-workdir.sh` (the repo a git command acts on, `cd <dir> &&` included), `pr-author.sh` (cached PR-authorship and repo-visibility predicates), and `hook-diag.sh` (re-emits captured stderr on exit 1/2 so block reasons are visible, and flags a hook that wrote to stderr on exit 0, where the harness discards it).
- **`destructive-guard/`** — Two-tier PreToolUse hook that hard-blocks irreversible operations (AWS data destruction, any push to main — force included, PR close, all four merge forms unless the user asked for the merge, bulk branch deletion) and turns risky-but-approvable ones (terraform destroy, force-push to a feature branch, `git reset --hard`, `gh issue` mutations) into explicit approval prompts. Worktree-aware push detection.
- **`merge-grant/`** — UserPromptSubmit hook that arms one-turn grants from the user's own words: asked for a merge, `destructive-guard` turns that turn's merges into a permission prompt instead of a hard block; asked to open a PR (typed, or picked in an `AskUserQuestion` menu), it skips the `gh pr create` prompt.
- **`commit-attribution-guard/`** — Hard-blocks AI attribution markers in commit messages and `claude/` branch prefix.
- **`worktree-preflight/`** — Blocks `git` write ops on a guarded repo's root when it's not on `main`.
- **`gha-lint-guard/`** — Pre-commit `actionlint` on staged `.github/workflows/*.yaml`; blocks on failure.
- **`model-effort-pin-guard/`** — SessionStart hook that re-pins `model` and `effortLevel` in user settings, because a `/model` pick persists itself as the new default. Pins come from env (`PIN_MODEL`, `PIN_EFFORT`).
- **`post-push-hygiene/`** — Reminds to resolve threads, update PR body, update tracker after a successful `git push`.
- **`pr-create-guard/`** — Blocks `gh pr create` when prerequisites are missing (zero diff, unpushed commits, uncommitted changes).
- **`pr-edit-counter/`** — Warns after 2+ body edits on the same PR.
- **`pre-push-quality/`** — Retired; migration stub points to repository lint/test commands and CI.
- **`review-verification-guard/`** — Retired; migration stub points to the review protocol/kernel and maintained review plugin.
- **`session-log/`** — Stop hook plus a reader: appends what each turn did to a per-session markdown log, so "where did that session stop" is a `grep` rather than a transcript reconstruction. Backs the `/recap` and `/sessions` skills.
- **`stateful-op-reminder/`** — Nudges on mutations to external systems — identity providers, IAM, databases, Kubernetes, Helm, Terraform apply — and appends a team heads-up template (draft a chat message for user approval — never auto-send; gates further mutations in the same change window).
- **`post-apply-state-check/`** — PostToolUse nudge after a successful `terraform apply` / `kubectl apply`: exit 0 proves syntax, not correctness — verify the resource live.
- **`settings-link-check/`** — SessionStart warning when the live `settings.json` stops being a symlink to the tracked dotfiles copy, so tracked edits silently stop reaching it. Reports the state and a summary of what differs.
- **`skill-arg-substitution-guard/`** — Blocks a `SKILL.md` or `commands/*.md` edit that writes a `$<digits>` token (an awk field, a price) the skill loader would silently replace with an argument.
- **`null-result-probe/`** — PostToolUse nudge: a command that returned nothing, or a scanner that reported a confident zero, while containing a construct that collapses silently (unquoted glob or expansion, git pathspec, `find` on `/tmp`) needs a control probe before the emptiness is read as a finding. Backs `rules/general/evidence-nulls.md`.
- **`rtk/`** — PreToolUse hook that rewrites Bash commands through RTK (Rust Token Killer) for token savings.
- **`statusline/`** — Statusline command showing directory, git branch/worktree, AWS profile, model name, effort level, context-window usage, PR review state, lines changed, and rate-limit reset.
- Plus auto-lint and AWS auth check examples. `ci-polling-guard/` and `kubectl-context-inject/` are retired migration stubs; see [RETIRED.md](RETIRED.md).

### `rules/`

Operational rules captured from real incidents. Organized by scope:

- **`general/`** — Cross-cutting principles that apply regardless of stack: git safety, PR workflows, operational discipline, idempotent operations, communication discipline, security scanning. Three of them are companion references in `config/global-CLAUDE-advanced.md` — `evidence-nulls.md` (result shapes that look like answers), `shell-traps.md` (commands that return a confident wrong answer instead of an error), and `review-verdicts.md` (which review state to pick, and how to grade a finding).
- **`devops/`** — DevOps-domain rules: AWS / IAM / SSO / VPC gotchas, Terraform module structure and discipline, GHA authoring, Kyverno validation style, ESO Go templates, Datadog config gotchas, S3 lifecycle, EKS+VPC gotchas, AWS WAF on ALB, security-group co-management, ElastiCache auth-token rotation.
- **`observability/`** — OTel resource-attribute precedence.
- **`frontend/`** — Stack-locked frontend rules (e.g., React + TanStack + Radix/Shadcn + Tailwind quality).

### `scripts/`

- **`inventory/`** — `generate-inventory.sh` regenerates `agent-roster.md` and `skill-inventory.md` from frontmatter on disk; `doc-maintenance.sh` validates `.claude/` doc health (path resolution, skill depth, inventory sync, cross-references). See the directory's README for scope and CI integration.

### `skills/`

User-invocable slash-command skills:

- **PR lifecycle** — `pr-check`, `pr-resolver` (review and finalize moved to [claude-reviewkit](https://github.com/asaphe/claude-reviewkit))
- **Session state** — `recap` (render the work in front of you and stop), `sessions` (query the session-log corpus written by the `session-log` hook)
- **Ticket / branch** — `open-ticket`
- **DevOps** — `eks-check`, `check-secret`, `new-gh-action`
- **Frontend** — `sentry-react`
- **Tooling evaluation** — `eval-tool`

### `hook-tests/`

Three harnesses for testing hooks, each covering an axis the others cannot: `run-fixtures.py` (one hook deeply, asserting the *outcome* rather than the exit code), `probe-hooks.py` (every hook shallowly, asserting which stream carried the payload — a hook can be individually correct and collectively unarmed), and `mutate-fixtures.py` (breaks each hook on purpose and requires the suite to notice). `fixture_env.py` builds the git state that state-reading guards decide from. `test-hook-contracts.py` pins event-aware output classification; `test-hook-diag.py` checks closed metadata logs and enforcement preservation. These are harness checks, not live Claude integration.

### `evals/`

Skill evaluation framework — validates that Claude Code routes queries to the correct skill and that skills produce expected behavior. Includes a Python runner, example trigger / functional eval JSON schemas, and a CI workflow pattern for PR reminders.

## Disclaimer

These examples reflect one team's usage patterns and conventions. They are opinionated, shaped by a specific stack (EKS, Terraform, Helm, multi-tenant SaaS), and may not suit every project. Take them as-is for inspiration — not as prescriptive best practices. What works well in a multi-service monorepo with many agents may be overkill for a smaller codebase, and the specific rules encoded here come from real incidents and corrections that may not apply to your context.

## How to Use

1. **Choose a route or browse** — Use the four declared recipes for copy-ready artifacts; read and adapt the remaining references with their dependencies.
2. **Start with what you need** — You don't need all of this. A single `CLAUDE.md` with good rules is more valuable than a complex multi-agent setup used poorly.
3. **Customize the specifics** — Replace `<org>`, `<company>`, `<your-cluster>` and other placeholders with your actual values. Adjust agent boundaries, review routing, and skill workflows to match your team's structure.

## Relationship to Other Directories

- **`tools/claude/guides/`** — Explains the *principles* behind each configuration area. These examples are *implementations* of those principles.
- **`tools/claude/scaffolding/`** (if present) — Minimal starting points for new projects. These examples show where a mature project ends up after months of refinement. Start with scaffolding, evolve toward these patterns as your project grows.
