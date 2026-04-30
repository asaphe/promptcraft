# Examples — Claude Code Configuration

Reference examples for `~/.claude/` and project-level `.claude/` configurations: agents, skills, hooks, rules, docs, scripts. Each example has been refined through daily use; company-specific details have been replaced with placeholders.

## Directory Structure

### `agents/`

Specialist agent definitions — operational agents (deployment, Terraform, K8s troubleshooting, Karpenter) and review agents (security, DevOps, bash, Python, Datadog, ClickHouse, agent-config, general code). Each agent has a focused domain, clear boundaries, and explicit deferral rules. See `docs/agent-roster.md` for the routing table; the count there is auto-generated from disk and won't drift.

### `config/`

- **`global-CLAUDE.md`** ⭐ — A `~/.claude/CLAUDE.md` template covering behavioral constraints, operational safety, review quality, git discipline, hook authoring, rule authoring, and CI/CD gotchas. **Start here if you're an infra / platform / DevOps engineer.** Drop it at `~/.claude/CLAUDE.md` and adjust the few opinionated sections (worktree convention, Task-Local Context) to your workflow.
- Annotated `settings.json` excerpts showing two key patterns:
  - **`settings-permissions.jsonc`** — Permission allowlists using Bash wildcards, MCP tool namespaces, WebFetch domain restrictions, and Skill permissions.
  - **`settings-hooks.jsonc`** — Hook configuration for PreToolUse command rewriting and statusline display.

### `docs/`

Supporting documentation referenced by agents and skills:

- **PR review kernel** — `pr-review-rules.md`, `pr-review-verification.md`, `pr-review-posting.md`, `pr-review-cleanup.md`, `comment-resolution-procedure.md`, `pr-review-policy.md`
- **Routing** — `agent-roster.md`, `skill-inventory.md`
- **Operational refs** — `production-safety-protocol.md`, `arc-runners-topology.md`, `aws-client-vpn-ops.md`, `network-policies-audit.md`, `eks-and-vpc-gotchas.md`
- **Terraform** — `terraform-module-anatomy.md`, `terraform-state-moves.md`
- **Datadog** — `datadog-pup.md`, `datadog-dashboard-codification.md`
- **Bash & CLI** — `bash-patterns.md`, `cli-gotchas.md`, `composite-action-spec.md`, `gha-reusable-workflow-patterns.md`
- **Doc / authoring** — `doc-authoring.md`, `doc-quality-checklist.md`
- **Codification templates** — `secret-naming-template.md`, `1password-caching.md`

### `hooks/`

- **`_lib/`** — Shared utilities sourced by hooks: `strip-cmd.sh` (heredoc / `-m` body stripping for pattern matching) and `hook-diag.sh` (re-emits captured stderr to Claude Code on exit 1/2 so block reasons are visible).
- **`destructive-guard/`** — Two-tier PreToolUse hook that hard-blocks irreversible operations (AWS deletions, push to main) and soft-blocks risky-but-approvable ones (PR ops, force-push, terraform destroy). Worktree-aware push detection.
- **`commit-attribution-guard/`** — Hard-blocks AI attribution markers in commit messages and `claude/` branch prefix.
- **`worktree-preflight/`** — Blocks `git` write ops on a guarded repo's root when it's not on `main`.
- **`gha-lint-guard/`** — Pre-commit `actionlint` on staged `.github/workflows/*.yaml`; blocks on failure.
- **`op-cache-cleanup/`** — Stop hook that purges `/tmp/op-cache-<session>/` when the session ends. Pairs with `scripts/op-cache.sh`.
- **`model-recommendation/`** — UserPromptSubmit advisory hook (config-driven) that nudges on model-tier mismatch.
- **`post-push-hygiene/`** — Reminds to resolve threads, update PR body, update tracker after a successful `git push`.
- **`pr-create-guard/`** — Blocks `gh pr create` when prerequisites are missing (zero diff, unpushed commits, uncommitted changes).
- **`pr-edit-counter/`** — Warns after 2+ body edits on the same PR.
- **`pre-push-quality/`** — Pre-push lint enforcement; blocks the push on lint failures.
- **`review-verification-guard/`** — Emits verification checklists before posting PR reviews / comments.
- **`stateful-op-reminder/`** — Nudges on mutations to external systems — identity providers, IAM, databases, Kubernetes, Helm, Terraform apply.
- **`rtk/`** — PreToolUse hook that rewrites Bash commands through RTK (Rust Token Killer) for token savings.
- **`statusline/`** — Statusline command showing directory, git branch, AWS profile, model name, and context-window usage.
- Plus several auto-lint, AWS auth check, kubectl context inject, and learning-capture hook examples.

### `rules/`

Operational rules captured from real incidents. Organized by scope:

- **`general/`** — Cross-cutting principles that apply regardless of stack: git safety, PR workflows, operational discipline, idempotent operations, communication discipline, security scanning, invisible characters, OTel resource-attribute precedence.
- **`devops/`** — DevOps-domain rules: AWS / IAM / SSO / VPC gotchas, Terraform module structure and discipline, GHA authoring, Kyverno validation style, ESO Go templates, Datadog config gotchas, S3 lifecycle, EKS+VPC gotchas, AWS WAF on ALB.
- **`frontend/`** — Stack-locked frontend rules (e.g., React + TanStack + Radix/Shadcn + Tailwind quality).

### `scripts/`

- **`op-cache.sh`** — Per-session 1Password value cache to avoid biometric re-prompts. Pairs with the `op-cache-cleanup` Stop hook.
- **`inventory/`** — `generate-inventory.sh` regenerates `agent-roster.md` and `skill-inventory.md` from frontmatter on disk; `doc-maintenance.sh` validates `.claude/` doc health (path resolution, skill depth, inventory sync, cross-references). See the directory's README for scope and CI integration.

### `skills/`

User-invocable slash-command skills:

- **PR lifecycle** — `pr-review`, `pr-check`, `pr-resolver`, `pr-finalize`
- **Ticket / branch** — `open-ticket`
- **DevOps** — `eks-check`, `check-secret`, `new-gh-action`
- **Frontend** — `sentry-react`
- **Tooling evaluation** — `eval-tool`
- **Knowledge management** — `scan-history`, `graduate-learnings`

### `evals/`

Skill evaluation framework — validates that Claude Code routes queries to the correct skill and that skills produce expected behavior. Includes a Python runner, example trigger / functional eval JSON schemas, and a CI workflow pattern for PR reminders.

## Disclaimer

These examples reflect one team's usage patterns and conventions. They are opinionated, shaped by a specific stack (EKS, Terraform, Helm, multi-tenant SaaS), and may not suit every project. Take them as-is for inspiration — not as prescriptive best practices. What works well in a multi-service monorepo with many agents may be overkill for a smaller codebase, and the specific rules encoded here come from real incidents and corrections that may not apply to your context.

## How to Use

1. **Browse for patterns** — These are reference implementations, not copy-paste templates. Read through to understand the patterns, then adapt for your project.
2. **Start with what you need** — You don't need all of this. A single `CLAUDE.md` with good rules is more valuable than a complex multi-agent setup used poorly.
3. **Customize the specifics** — Replace `<org>`, `<company>`, `<your-cluster>` and other placeholders with your actual values. Adjust agent boundaries, review routing, and skill workflows to match your team's structure.

## Relationship to Other Directories

- **`tools/claude/guides/`** — Explains the *principles* behind each configuration area. These examples are *implementations* of those principles.
- **`tools/claude/scaffolding/`** (if present) — Minimal starting points for new projects. These examples show where a mature project ends up after months of refinement. Start with scaffolding, evolve toward these patterns as your project grows.
