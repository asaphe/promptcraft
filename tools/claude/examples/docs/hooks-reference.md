# Hooks Reference

An example of documenting a full hook set as an execution-order + cost reference. Execution order within each event follows the array order in `settings.json`.

**The rows are an illustration of a real config, not an index of this repo.** Some of the hooks named below are published under [`../hooks/`](../hooks/) and some are not — the names are here to show what a row looks like and how the events compose, so treat any given filename as a worked example rather than a file you can open. Adapt the org-specific rows (context injection, cluster context, repo identity) to your own setup.

**Each heading states its entry count, and that is the technique worth copying.** A count is the cheapest drift check available: if a heading disagrees with your `settings.json`, the doc is stale, and you find that out by counting rather than by reading. Keep the counts accurate or don't write them — a stale count is worse than none, because it asserts a check that isn't happening. The numbers below describe *this example*, not any real installation, so they are the pattern to imitate rather than figures to compare your own config against. Plugin-wired hooks are registered separately and are **not** included; see the last section.

## SessionStart — 3 entries

| Hook | Matcher | Purpose | Output | Cost |
|------|---------|---------|--------|------|
| `engineering-rules-inject.sh` | — | Injects universal engineering rigor rules | ~250 chars stdout → context | Once per session (~17ms) |
| `org-context-inject.sh` | — | Injects org operating context (worktree, cloud profile, repos) — cwd-gated | ~200 chars stdout → context (silent outside org cwd) | Once per session (~5ms) |
| `post-compact-reinject.sh` | `compact` | Re-injects behavioral rules + git state + active PRs after compaction | Plain-text stdout → context | Per compaction |

Note the matcher on the third row. Re-injecting context after compaction is a **`SessionStart` entry with `matcher: "compact"`**, not a `PostCompact` hook — `PostCompact` is side-effects-only and cannot add anything to the context window. See [`hooks/post-compact-reinject/`](../hooks/post-compact-reinject/) for the full reasoning.

## PreCompact — 1 entry

| Hook | Purpose |
|------|---------|
| `session-log-precompact.sh` | Asks for a session-log entry before compaction, via `additionalContext`. Never blocks |

Compaction is the one boundary where in-session reasoning is destroyed while anything derived from it survives — which is what makes spending tokens here worthwhile.

## UserPromptSubmit — 6 entries (every prompt, in order)

| Hook | Purpose | Output | Cost |
|------|---------|--------|------|
| `engineering-rules-anchor.sh` | Engineering rules re-anchor | ~160 chars additionalContext | **Once per session** (stamp) |
| `clone-id-inject.sh` | Identifies which repo clone | ~50 chars additionalContext | **Once per session** (stamp) |
| `aws-auth-check.sh` | Validates SSO tokens, injects profile status | ~100 chars additionalContext | **Once per session** (~2.2s first call, <5ms after) |
| `model-recommendation.sh` | Warns on model/task mismatch | ~80 chars additionalContext (on mismatch only) | Every prompt (reads transcript tail) |
| `session-budget-warn.sh` | Nudges `/clear` when session is very old or context is very large | ~300 chars additionalContext (throttled 1/hr per session) | Every prompt (stat + transcript tail) |
| `pr-context-inject.sh` | Injects active PR URLs from all repos | 1–5 lines additionalContext | **Once per session** (stamp), seeded from cache |

## PreToolUse: Bash — 15 entries (in order)

| Hook | Matcher | Purpose | Output | Cost |
|------|---------|---------|--------|------|
| `rtk-rewrite.sh` | All Bash | Rewrites commands to use a token-optimizing proxy | Rewrites tool input | Per call, fast |
| `kubectl-context-inject.sh` | All Bash | Injects `--context <your-cluster>` on kubectl/helm | Rewrites tool input | Per call, exits early if no k8s cmd |
| `ci-polling-guard.sh` | `sleep *` | Blocks polling loops | Blocks or warns | Conditional |
| `op-read-guard.sh` | `op *` | Blocks raw secret reads, redirects to a masked cache ([claude-secret-guard](https://github.com/asaphe/claude-secret-guard)) | Blocks or warns | Conditional |
| `stateful-op-reminder.sh` | All Bash | Nudges on external state mutations | `additionalContext` reminder | Per call, pattern-match only |
| `destructive-guard.sh` | All Bash | Blocks/soft-blocks destructive ops | Hard block (exit 2) or soft block | Per call, most calls exit early |
| `review-verification-guard.sh` | `gh *` | Enforces review verification before posting | Blocks if missing | Conditional |
| `agent-config-review-guard.sh` | `git commit*` | Flags agent config changes on commit | Warning | Conditional |
| `commit-attribution-guard.sh` | `git *` | Hard-blocks AI attribution markers in commit messages and bot branch prefixes | Hard block (exit 2) | Conditional |
| `worktree-preflight.sh` | `git *` | Hard-blocks git WRITE ops on a repo root when root is not on main (signals another session active) | Hard block (exit 2) | Conditional |
| `gha-lint-guard.sh` | `git commit*` | Runs actionlint on GHA workflows | Blocks on lint errors | Conditional |
| `agent-config-review-guard.sh` | `git push*` | Flags agent config changes on push | Warning | Conditional |
| `pre-push-lint-guard.sh` | `git push*` | Runs the linter before push | Blocks on errors | Conditional |
| `pr-create-guard.sh` | `gh *` | Pre-flight checklist for PR creation, and for `gh stack submit` | Blocks or warns | Conditional |
| `session-log.sh` | Stop | Appends the turn to a per-session log; nudges when its newest `state` line is stale | `systemMessage` to the user | Conditional |
| `pr-edit-counter.sh` | `gh pr edit*` | Tracks PR edit count | Advisory | Conditional |

## PreToolUse: Edit / MultiEdit / Write — 3 entries

| Hook | Purpose | Output |
|------|---------|--------|
| `memory-guard.sh` | Blocks writes to per-project memory paths for specific clones | Hard block (exit 2) |
| `comment-discipline-guard.sh` | Blocks multi-line code-comment blocks before the edit lands. Code files only (markdown excluded), with carve-outs for suppression directives, shebangs and doc-pointers | Hard block (exit 2) |
| `worktree-preflight.sh` | Blocks edits on a repo root when the root is not on main | Hard block (exit 2) |

`comment-discipline-guard.sh` is worth calling out as a *design* example: comment discipline is already stated as a rule, in context every session, and it still gets violated. That makes it an application gap rather than a knowledge gap — which is the case where a hook earns its keep over another line of prose.

## PreToolUse: Agent — 1 entry

| Hook | Purpose |
|------|---------|
| `team-spawn-sendmessage-guard.sh` | Warns (advisory, never blocks) when a named, team-addressable `Agent` spawn uses a `subagent_type` whose definition omits `SendMessage` from its `tools:` frontmatter — the signature of a teammate whose system prompt promises messaging that isn't in its callable tool list |

`PreToolUse` matches on tool name, so `Agent` is a matcher like any other. Guards on agent *spawns* are an under-used class: they are the only place to catch a misconfigured delegation before it burns a full subagent run.

## PreToolUse: issue-tracker create — 1 entry

| Hook | Purpose |
|------|---------|
| `ticket-creation-guard.sh` | Enforces ticket hygiene before creation |

An MCP tool is matched by its full tool name. One script registered against several tool names counts as one entry per registration — keep that in mind when reconciling the count against `settings.json`.

## PostToolUse: Bash — 4 entries (in order)

Read this section before writing any `PostToolUse` hook — the payload shape has two traps that both fail silently.

**The field carrying the tool's result is `tool_response`, not `tool_result`.** The latter is the transcript's name for what the model sees. A hook reading `.tool_result.stdout` gets an empty string for every command ever run, so a positive gate on the result never fires and a negative one never suppresses. Both look like a working hook that simply had nothing to say.

**`tool_response` carries no exit code under any name** — `.exit_code` and `.exitCode` both resolve to empty. So a hook cannot report whether the command it just observed succeeded; it has to infer that from the response content, or not claim it at all. A status column written from this payload records "ran", never "failed".

**The event still fires when the command exits non-zero — "fired" is not "succeeded".** Verified on Claude Code 2.1.263 by counting a `PostToolUse` hook's own log lines across a controlled run: exits 42, 127 and 3 each produced a record, exactly as a successful command did. Do not build a hook whose success signal is the event firing. If you carry that assumption into a test, make the fixture prove it — a probe that supplies its own payload with an invented `exit_code` field will happily validate a hook that could never read one.

| Hook | Matcher | Purpose |
|------|---------|---------|
| `terraform-output-reminder.sh` | `terraform *` | Reminds to inspect actual output, not just exit code |
| `post-push-hygiene.sh` | `git push*` | Invalidates PR cache; post-push checklist (detects `.tf` changes, nudges PR body/tracker update) |
| `tf-apply-reminder.sh` | `terraform plan*` | Reminds to apply after reviewing plan |
| `pr-state-cache-invalidate.sh` | `gh pr *` | Invalidates PR cache on ready/close/reopen to prevent stale statusline badge |

## Stop — 2 entries

| Hook | Purpose |
|------|---------|
| `session-quality-capture.sh` | Records session quality metrics |
| `op-cache-cleanup.sh` | Purges the per-session secret caches ([claude-secret-guard](https://github.com/asaphe/claude-secret-guard)) |

## SessionEnd — 1 entry

| Hook | Purpose |
|------|---------|
| `terminal-restore.sh` | Undoes per-session terminal side effects (tab colour, title) |

Do not make `SessionEnd` the only place cleanup happens. A crash, a killed terminal, or a machine losing power ends the session without running it, so anything whose absence leaves a security-relevant artifact behind — a cached secret, a decrypted file — wants a `Stop` hook as well *and* an age-based sweep on the next `SessionStart` to catch whatever a previous session left. The sweep is the part people skip, and it is the only one that recovers from a hard kill.

## Plugin-wired hooks — not in `settings.json`

Plugins register their own hooks through each plugin's `hooks/hooks.json`. Those fire alongside everything above, so the real per-session surface is larger than the counts in this file, and `settings.json` alone is not an inventory of what runs.

| Plugin | Event | Hook |
|--------|-------|------|
| [`claude-secret-guard`](https://github.com/asaphe/claude-secret-guard) | UserPromptSubmit | `paste-secret-guard.sh` |
| [`claude-secret-guard`](https://github.com/asaphe/claude-secret-guard) | PreToolUse `Read` | `read-secret-guard.sh` — `ask`-gates reads of secret-shaped filenames so contents don't silently enter context |
| [`claude-secret-guard`](https://github.com/asaphe/claude-secret-guard) | PreToolUse `Write\|Edit\|MultiEdit` | `write-secret-guard.sh` |
| [`claude-secret-guard`](https://github.com/asaphe/claude-secret-guard) | PreToolUse `Bash` | `bash-secret-authority.sh` |
| [`claude-secret-guard`](https://github.com/asaphe/claude-secret-guard) | Stop | `op-cache-cleanup.sh` |
| [`claude-intent-router`](https://github.com/asaphe/claude-intent-router) | UserPromptSubmit | `intent-router.sh` |
| [`claude-learning-loop`](https://github.com/asaphe/claude-learning-loop) | Stop / PreCompact | `learn-suggest.sh`, `wrap-up-precompact-reminder.sh` |

Two consequences worth internalizing. A hook you moved into a plugin and a copy left behind in `settings.json` will **both** fire, and the pair can disagree — the plugin's version having a fix the local copy never got is the common shape. And when a plugin is disabled, a guard you believe is running silently stops; check the plugin roster, not just `settings.json`, before asserting that anything is guarded.

`permissions.deny` in `settings.json` separately hard-blocks fixed high-value paths (`~/.aws/credentials`, `~/.aws/sso/cache/**`, `~/.ssh/**`). That is a permission rule rather than a hook, and it fires whether or not any guard plugin is enabled.

## Reading the `hook-diag` log

[`_lib/hook-diag.sh`](../hooks/_lib/hook-diag.sh) writes one record per hook decision. The record format carries two properties that are load-bearing rather than cosmetic, and both defend the same failure: a log that *reports a dead hook as active*, which is a false all-clear in the one tool whose entire job is detecting dead hooks.

- **Fields are newline-free by construction.** `\n` and `\r` are flattened to spaces in the command, stderr and input-head fields at capture time. Without that, a logged command containing a line equal to the record separator — a heredoc, a markdown rule, a prompt separator — starts a phantom record, and the lines after it are read as that record's own header fields. The serious half is that a command which merely *mentions* a hook name then gets counted as that hook having run.
- **The reader anchors by position.** A timestamp field is accepted only as a record's first line and only if it parses as a timestamp; the hook-name field only as its second. That keeps records already on disk from forging either. The two defences are independent — the writer's flattening protects new records, the reader's anchoring covers the corpus you already have — so do not drop one because the other exists.

Two practical traps when analysing the corpus:

- **The log file is shared, and other checkouts write to it.** Any copy of `hook-diag.sh` on the machine defaults to the same log path, so a second working tree running its own eval suite contaminates your counts with synthetic commands — and it inflates exactly the commands the corpus gets consulted for, since fixture data is repetitive by design. Emit a field that only your writers set (a session id) and filter on it, rather than trying to contain the foreign writers.
- **Command text is flattened, so a trailing newline becomes a trailing space.** Comparing stripped fixture text against unstripped log text returns zero matches and reads as a clean corpus. Strip both sides.

## Notes

- `destructive-guard.sh`, `stateful-op-reminder.sh`, `rtk-rewrite.sh`, and `kubectl-context-inject.sh` run on every Bash call and exit early for non-matching commands — unavoidable, they need broad coverage.
- An unconditional hook should think twice before sourcing `hook-diag.sh`: it writes a record on every single call, which shortens the log's retention window for every other hook.
- `terraform-output-reminder.sh` uses a narrow `if: "Bash(terraform *)"` matcher to avoid firing on every Bash call.
- The `aws-auth-check.sh` first-prompt cost is inherent to the STS calls through SSO; acceptable given the multi-hour token TTL.
- PR cache keys are repo-scoped (`<prefix>-<repo>-<branch>`) to prevent collision when multiple repos share a branch name.
- `strip-cmd.sh` (not a hook itself) is sourced by the command-matching guards to normalize the command before pattern matching — it replaces heredoc bodies and `-m`/`--message` argument contents with placeholders so dangerous-pattern regexes don't false-positive on commit-message text.
- Hooks with narrow `if:` matchers (e.g., `Bash(git push*)`, `Bash(gh pr create*)`) don't need `strip-cmd` because the harness filters before they fire.
- **Record each entry's timeout deliberately.** Timeouts are per-entry, and the default is generous enough that a slow hook degrades every prompt before anyone notices. Give the unconditional hooks the tightest budget that still lets them finish, and the ones that shell out to a network call the longest.
