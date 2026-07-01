# Hooks Reference

An example of documenting a full hook set as an execution-order + cost reference. Execution order within each event follows the array order in `settings.json`. Individual hooks referenced here are published under `../hooks/`. Adapt the org-specific rows (context injection, cluster context, repo identity) to your own setup.

## SessionStart

| Hook | Purpose | Output | Cost |
|------|---------|--------|------|
| `engineering-rules-inject.sh` | Injects universal engineering rigor rules | ~250 chars stdout → context | Once per session (~17ms) |
| `org-context-inject.sh` | Injects org operating context (worktree, cloud profile, repos) — cwd-gated | ~200 chars stdout → context (silent outside org cwd) | Once per session (~5ms) |

## UserPromptSubmit (every prompt, in order)

| Hook | Purpose | Output | Cost |
|------|---------|--------|------|
| `engineering-rules-anchor.sh` | Engineering rules re-anchor | ~160 chars additionalContext | **Once per session** (stamp) |
| `clone-id-inject.sh` | Identifies which repo clone | ~50 chars additionalContext | **Once per session** (stamp) |
| `aws-auth-check.sh` | Validates SSO tokens, injects profile status | ~100 chars additionalContext | **Once per session** (~2.2s first call, <5ms after) |
| `model-recommendation.sh` | Warns on model/task mismatch | ~80 chars additionalContext (on mismatch only) | Every prompt (reads transcript tail) |
| `session-budget-warn.sh` | Nudges `/clear` when session is very old or context is very large | ~300 chars additionalContext (throttled 1/hr per session) | Every prompt (stat + transcript tail) |
| `pr-context-inject.sh` | Injects active PR URLs from all repos | 1–5 lines additionalContext | **Once per session** (stamp), seeded from cache |

## PreToolUse: Bash (every Bash call, in order)

| Hook | Matcher | Purpose | Output | Cost |
|------|---------|---------|--------|------|
| `rtk-rewrite.sh` | All Bash | Rewrites commands to use a token-optimizing proxy | Rewrites tool input | Per call, fast |
| `secretsmanager-proxy.sh` | `aws secretsmanager*` | Routes secrets through a safe proxy | Modifies command | Conditional |
| `kubectl-context-inject.sh` | All Bash | Injects `--context <your-cluster>` on kubectl/helm | Rewrites tool input | Per call, exits early if no k8s cmd |
| `ci-polling-guard.sh` | `sleep *` | Blocks polling loops | Blocks or warns | Conditional |
| `op-read-guard.sh` | `op *` | Guards password-manager biometric calls | Blocks or warns | Conditional |
| `stateful-op-reminder.sh` | All Bash | Nudges on external state mutations | stderr reminder | Per call, pattern-match only |
| `destructive-guard.sh` | All Bash | Blocks/soft-blocks destructive ops | Hard block (exit 2) or soft block | Per call, most calls exit early |
| `review-verification-guard.sh` | `gh *` | Enforces review verification before posting | Blocks if missing | Conditional |
| `agent-config-review-guard.sh` | `git commit*` | Flags agent config changes on commit | Warning | Conditional |
| `commit-attribution-guard.sh` | `git *` | Hard-blocks AI attribution markers in commit messages and bot branch prefixes | Hard block (exit 2) | Conditional |
| `worktree-preflight.sh` | `git *` | Hard-blocks git WRITE ops on a repo root when root is not on main (signals another session active) | Hard block (exit 2) | Conditional |
| `gha-lint-guard.sh` | `git commit*` | Runs actionlint on GHA workflows | Blocks on lint errors | Conditional |
| `agent-config-review-guard.sh` | `git push*` | Flags agent config changes on push | Warning | Conditional |
| `pre-push-lint-guard.sh` | `git push*` | Runs the linter before push | Blocks on errors | Conditional |
| `pr-create-guard.sh` | `gh pr create*` | Pre-flight checklist for PR creation | Blocks or warns | Conditional |
| `pr-edit-counter.sh` | `gh pr edit*` | Tracks PR edit count | Advisory | Conditional |

## PreToolUse: Write

| Hook | Purpose |
|------|---------|
| `memory-guard.sh` | Blocks writes to per-project memory paths for specific clones |

## PreToolUse: issue-tracker create

| Hook | Purpose |
|------|---------|
| `ticket-creation-guard.sh` | Enforces ticket hygiene before creation |

## PostToolUse: Bash (every Bash call, in order)

| Hook | Matcher | Purpose |
|------|---------|---------|
| `terraform-output-reminder.sh` | `terraform *` | Reminds to inspect actual output, not just exit code |
| `post-push-hygiene.sh` | `git push*` | Invalidates PR cache; post-push checklist (detects `.tf` changes, nudges PR body/tracker update) |
| `tf-apply-reminder.sh` | `terraform plan*` | Reminds to apply after reviewing plan |
| `pr-state-cache-invalidate.sh` | `gh pr *` | Invalidates PR cache on ready/close/reopen to prevent stale statusline badge |

## PostCompact

| Hook | Purpose |
|------|---------|
| `post-compact-reinject.sh` | Re-injects behavioral rules + git state + active PRs after compaction |

## Stop

| Hook | Purpose |
|------|---------|
| `session-quality-capture.sh` | Records session quality metrics |
| `op-cache-cleanup.sh` | Purges per-session password-manager cache |

## Notes

- `destructive-guard.sh`, `stateful-op-reminder.sh`, `rtk-rewrite.sh`, and `kubectl-context-inject.sh` run on every Bash call and exit early for non-matching commands — unavoidable, they need broad coverage.
- `terraform-output-reminder.sh` uses a narrow `if: "Bash(terraform *)"` matcher to avoid firing on every Bash call.
- The `aws-auth-check.sh` first-prompt cost is inherent to the STS calls through SSO; acceptable given the multi-hour token TTL.
- PR cache keys are repo-scoped (`<prefix>-<repo>-<branch>`) to prevent collision when multiple repos share a branch name.
- `strip-cmd.sh` (not a hook itself) is sourced by the command-matching guards to normalize the command before pattern matching — it replaces heredoc bodies and `-m`/`--message` argument contents with placeholders so dangerous-pattern regexes don't false-positive on commit-message text.
- Hooks with narrow `if:` matchers (e.g., `Bash(git push*)`, `Bash(gh pr create*)`) don't need `strip-cmd` because the harness filters before they fire.
