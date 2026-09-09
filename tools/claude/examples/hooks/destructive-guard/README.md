# Destructive Operation Guard

PreToolUse hook with two-tier blocking for destructive operations.

## Two-Tier Design

| Tier | Mechanism | Override by `Bash(*)`? | Use for |
|------|-----------|------------------------|---------|
| **Hard block** | `exit 2` + stderr | No — always blocks | Irreversible data loss and forbidden PR ops (AWS deletions, push/force-push to main, PR close/merge) |
| **Soft block** | JSON `permissionDecision: ask` + `exit 0` | Yes — user can approve | Risky but approvable (PR create, force-push to a branch, terraform destroy) |

Hard blocks stop the tool call unconditionally — no override is possible. The user must run the command themselves in their terminal.

Soft blocks emit `permissionDecision: ask` JSON on stdout and exit 0. Claude Code shows the reason in a permission prompt where the user can approve or deny — even when `Bash(*)` is in the allow list.

## What It Blocks

### Hard Blocks (irreversible)

| Pattern | Why |
|---------|-----|
| `git push` to main/master | Must go through PRs |
| `git push --force` to main/master | Rewrites shared history on default branch |
| `gh pr close` | Loses PR context — never without explicit user instruction |
| `gh pr merge`, `gh api .../pulls/N/merge`, `gh stack merge` | The user merges PRs themselves — all three forms, no approval path |
| `git clean -f` | Permanently deletes untracked files |
| `git stash drop/clear` | Permanently discards stashed changes |
| Bulk `git branch -d/-D` (xargs, loop, or several names) | One bad glob wipes hundreds of refs |
| `aws * delete-*`, `aws s3 rm`, `aws ec2 terminate-*` | Cloud resource destruction |
| `aws dynamodb delete-table`, `aws kms schedule-key-deletion`, and peers | Destroys stored data, its backups, or the key that decrypts it |

### Soft Blocks (confirm first)

| Pattern | Why |
|---------|-----|
| `gh pr create` | Visible shared action |
| `gh stack submit/link/unstack` | Acts on every PR in the stack, not one |
| `gh issue <mutating verb>`, `gh api .../issues` with a method or field | Files an external artifact under your GitHub identity |
| `gh run delete` | Permanently removes CI run history |
| `git push --force`/`-f`/`+refspec` to a non-default branch | History rewriting (reversible via reflog) |
| `git push --delete` / `git push origin :branch` | Deletes a remote branch, auto-closing any PR on it |
| `git reset --hard` | Discards uncommitted changes (recoverable via reflog) |
| `git branch -D` (single), `git checkout --`, `git restore` | Discards local changes |
| `terraform destroy/state rm/force-unlock/workspace delete` | Infrastructure changes |
| `kubectl delete/drain/cordon/scale/rollout undo/patch` | Live cluster mutations |
| `helm uninstall/rollback` | Release changes |
| Any `aws <service> delete-*` / `remove-*` / `terminate-*` / `purge-*` / `deregister-*` / `destroy-*` | Default-deny for the whole destructive verb family |

## Worktree-Aware Push Detection

The guard correctly handles worktree-based workflows where the repo root stays on `main`:

- `cd /tmp/worktree && git push origin branch` — detects the `cd` and checks the branch in the target directory, not the hook's CWD
- `git push origin feature-branch` — recognizes a named non-main branch is safe
- `git push origin local:remote` — recognizes explicit refspecs are safe (unless pushing TO main)
- `git push origin feature:main` — correctly blocks pushing to main via refspec

This prevents false positives when the hook's working directory is on `main` but the push targets a feature branch in a worktree.

## Parser hardening

Every rule here is a regex over command *text*, so the parser is where this hook fails silently rather than loudly. These habits keep it honest — each one is a fix for a miss that was reproduced, not imagined:

- **Expand `~` and `$HOME` in an extracted path.** A path lifted out of the command string is never shell-expanded, so `cd ~/repo && git push` leaves `~/repo` literal, `git -C '~/repo'` fails, the branch reads empty, and empty is not `main` — the push to `main` sails through. Whichever way the lookup is wired, an unresolved path **fails open**. `expand_path` resolves `~`, `~/…`, `$HOME` and `${HOME}` before any lookup.
- **Match a token, not a substring.** Extracting `push[^;&|]*` finds its first hit inside `git -C /tmp/x-push-y push origin main` — in the *path* — so the ref parsed out is `origin` and the guard stays quiet on a push to `main`. `push_args` walks whitespace-separated tokens and starts after the one that is exactly `push`.
- **Isolate separators before tokenising.** A token walk splits on whitespace, so `git push origin main;echo done` makes `main;` a single field. Dropping that field for containing a separator drops the ref with it, and the push to `main` reads as ref-less. `push_args` spaces out `;`, `&` and `|` first, so the ref survives and only the separator ends the scan.
- **Extract from the *stripped* command.** Ref extraction on the raw command lets a bare `push` inside a `-m` message synthesise a ref: `git commit -m "fix push for main branch" && git push origin feature-x` parsed `main` out of the message and hard-blocked ordinary feature work, with no approval path.
- **`HEAD` is not a ref name.** `git push origin HEAD` pushes whatever branch is checked out, so treating `HEAD` as an explicit ref skips the branch lookup entirely and misses a push to `main`. It is cleared so the lookup runs.
- **Evaluate the push rule per segment, not once per command.** `push_args` starts at the first token equal to `push`, so a bare `push` anywhere earlier — in an `echo`, a `grep`, a PR body — captured the extraction and left the real `git push origin main` behind it completely unguarded. The rule now walks each segment that carries a `git … push` and blocks on the first that targets the default branch.
- **Unquote every extracted value, not most of them.** `PUSH_DIR` and `CMD_TARGET` were unquoted and `PUSH_REF` was not, so `git push origin "main"` compared `"main"` against `main` and passed. A partially-applied normalisation reads as done.
- **Extract a loop body; don't match across it.** A greedy `.*` before `do` anchors on the *last* one, so a second loop — or a later sentence containing the word `do` — replaced the real body and disarmed the rule. Non-greedy, and repeated over every `do…done` pair.
- **Resolve the working directory per segment, tracking `cd` as the shell does.** The branch-switch check took the first `-C` anywhere in the command, so `git -C <other-repo> log && git checkout main` resolved against the repo the *read* named. It now walks segments, letting a `cd` move the effective directory for everything after it and letting a `-C` bind only to its own invocation — which also stops one `git checkout -- .` from disarming a real cross-repo checkout beside it.
- **Scope a negative test to one segment.** A `! grep` over the whole command line is satisfiable by *any* segment, so `gh api -X GET …/labels && gh api …/issues -f title=x` had its own read disarm the gate for the mutation beside it. `seg_matches` splits on unquoted separators first (via `_lib/split-cmd-segments.pl`) and requires the positives and the absence of the negative to hold within one segment. If the splitter is unreadable it falls back to whole-command matching — the behaviour it replaced, rather than silence.
- **Confine a flag test to the segment that owns it.** Scanning the whole command line for a force flag fires on an unrelated `rm -f` after the push; scanning only the first `push` misses `git push origin a && git push --force origin b`. The `PUSH_SEG` prefix (`push[^|;&]*`) does neither: `grep` still finds a later push, and no match can cross `|`, `;` or `&`.
- **Normalize whitespace with its quote context.** Inter-token tabs become spaces and escaped newlines are removed by the quote helper. Quoted data keeps its original characters in the extraction view.
- **Fail closed on preprocessing errors.** The hook checks `jq` and `perl` at entry and exits 2 with a named reason if either is absent. A missing quote helper or detected parse error also blocks, before an empty result can reach the fast-path gate.
- **Derive matching and extraction views from the original syntax.** `_lib/strip-quoted-args.pl --values` retains argument values in `CMD_STRIPPED`; the default mode blanks multi-word quoted data in `CMD_MATCH`. Both unquote parsed simple tokens such as `"gh"`, so quoted executables still match. Each nested substitution has its own quote context: the quotes inside `"$(printf "$(printf path)")"` cannot consume a later command. Static payloads handed to recognized shells remain visible.
- **Descend into command substitutions.** `$()` and backticks execute before their surrounding command, including inside double quotes and arithmetic expansion. The quote helper decodes legacy backticks one level at a time and renders them as `$()`. The splitter emits inner commands separately without closing delimiters, so a push to `main)` is identified as a push to `main`. Single-quoted and escaped spellings stay literal. Checkout uses a typed scoped pass to restore its directory after a substitution.
- **Keep executable heredoc expansions.** An ordinary unquoted heredoc can execute `$()` and backticks even when its body looks like quoted prose. The helper preserves these expansions while discarding literal body text, consumes multiple bodies in order, and resumes at the command after each terminator. Quoting any part of the delimiter disables expansion. Interpreter classification belongs to the command receiving that body: an earlier shell command cannot turn a later `cat` body into code, and tested shell wrappers still preserve executable stdin. Script and inline-command modes retain stdin as data. Tests cover mixed quoting, `<<-`, continuations, and here-strings.

This remains a targeted command-surface detector, not full Bash grammar or an execution sandbox. Commands assembled dynamically through variables or arbitrary `eval` payloads are not resolved. Comment text is inspected conservatively in an isolated segment. Detected parse errors can therefore block unsupported syntax as well as malformed commands.

Two related defaults: a target that is not a git repository never counts as a cross-repo branch switch (without that test, every `cd <non-repo> && git checkout` blocked), and a `PUSH_DIR` that does not resolve falls back to the session's own branch rather than to an empty string.

## Why `--dry-run` is not exempt

`git clean -fdn` previews rather than deletes, so exempting it looks free. It is not: the exemption is a second `grep` over the same command line, and `git clean -fdn && git clean -fd` satisfies it in the first segment while the second segment does the real delete. The block would then be lifted for the destructive half.

The same argument applies to `git push --dry-run origin main`, which is likewise blocked. In both cases the cost of the false positive is one command the user runs themselves; the cost of the fail-open is the thing the hook exists to prevent. A per-segment exemption would be sound, but it is strictly more machinery than the false positive is worth.

## Bulk branch deletion

Deleting one branch is a soft ask: a branch is a ref, and the reflog holds the tip for `gc.reflogExpire` (90 days by default), so it is recoverable.

Bulk deletion is a hard block in three shapes — `xargs`, a `for`/`while` loop, and several branch names in one command. What changes is not the delete but the blast radius: a glob that matches more than intended wipes hundreds of refs in one call, and no reflog makes that reviewable afterwards. Both `-d` and `-D` are blocked in the bulk forms, and the message says so, because a message naming only `-D` invites a retry with `-d` that fails the same way.

The loop form **extracts the body between `do` and `done`** rather than matching across it. Matching across fails in both directions: a multi-line body puts arbitrarily many separators between the loop header and the delete, so a real bulk delete written over three lines matched nothing, while `for x in a b; do echo $x; done && git branch -D one` matched and hard-blocked a single delete that was never in the loop.

## AWS coverage

Two layers, because a per-service denylist always trails the API:

- A **soft catch-all** on the whole destructive verb family — `delete-`, `remove-`, `terminate-`, `purge-`, `deregister-`, `destroy-` — so a verb AWS ships tomorrow prompts instead of passing silently. Membership in the family is the trigger, not membership in a list.
- A **hard list** for the operations that destroy stored data, its backups, or the key that decrypts it. This tier has no approval path at all, which is exactly why it is enumerated: a service missing from it still hits the catch-all above and prompts, so the list only has to name what must never be approvable in one keystroke.

The catch-all keys on `<lowercase token> <destructive verb>-…` inside one segment. That is deliberately loose, and it over-fires when an *argument value* sits in that position — `aws ecs list-tasks --cluster prod delete-me` prompts. Tightening it to a true command position would trade a prompt on a read for a silent pass on a verb the list has not caught up with, which is the wrong direction for a default-deny. Flag values that follow a `--flag` (`--filters Values=terminate-me`, `--name delete-flag`) do *not* fire, because the token before the verb must not itself start with `-`.

## Cost per call

This is a `PreToolUse` hook: it runs before **every** Bash tool call, so its own latency is a tax on everything else.

Preprocessing invokes the quote parser twice, once for matching and once for extraction. These invocations avoid adding another multi-record output protocol between the parser and Bash, at the cost of two syntax walks and Perl startups. The rule cascade adds roughly 60 `echo | grep` fork pairs and a Perl segment split; checkout also requests scoped records. A fast-path gate skips that cascade when the parsed command names none of `git`, `gh`, `aws`, `kubectl`, `helm`, `terraform`, `xargs`.

That gate is a fail-**open** if it is ever wrong: a rule keyed on a binary the gate omits silently stops firing, and no eval case would notice unless one happened to cover it. So the token list is not trusted as written. `.claude/scripts/check-guard-gate.py` re-derives every rule's leading binary from the hook source, fails if the gate omits one, and separately asserts that every case the suite expects to act on survives the gate. It is itself mutation-tested — dropping a token from `GUARD_TOOLS` must make it fail.

Measured median over 12 local runs with the expansion parser, using macOS Bash 3.2:

| Command | Median |
|---|--:|
| `ls -la` (names no guarded binary) | 189 ms |
| `git status` (gate passes, cascade runs) | 513 ms |

These timings depend on host load and are not a performance guarantee. Both paths pay for preprocessing; commands naming a guarded tool also pay for the rule cascade. Each segment format is cached within the invocation.

## Reporting every trigger

`SOFT_REASON` used to be overwritten by each matching rule, so `terraform destroy && kubectl scale` reported only `kubectl scale` — the *less* consequential of the two — and the ask log attributed the prompt to it. Triggers now accumulate: the first is the headline, each additional one is appended as an `ALSO:` line, so a compound command shows everything it is about to do.

## Keeping the two copies honest

This hook ships twice: `tools/claude/examples/hooks/destructive-guard/` is what people install, `.claude/hooks/` is what this repo runs and the only copy the eval suite exercises. A fix applied to one and not the other is invisible — the suite stays green against the copy that was fixed while adopters get the copy that was not. `.claude/scripts/check-mirrors.py` fails CI on any drift, and is mutation-tested the same way.

## Installation

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "/path/to/destructive-guard.sh"
          }
        ]
      }
    ]
  }
}
```

Requires `jq` and `perl` on PATH, plus `../_lib/hook-diag.sh`, `../_lib/strip-quoted-args.pl`, and `../_lib/split-cmd-segments.pl` installed under the same parent directory as the hook. Update the guard and helpers together.

## Testing

The repo's own copy of this hook is covered by `.claude/evals/destructive-guard/cases.json`, run by `.claude/evals/runner.py`. Cases assert an exit code and a substring, on the combined output (`expected_output`) or on one channel (`expected_stdout` / `expected_stderr`) when the channel is the behaviour under test.

Cases whose behaviour depends on real git state carry `setup`/`cleanup` shell snippets — branch detection cannot be exercised without a repository to detect a branch in. A failing `setup` fails the case rather than letting it pass against a fixture that was never created.

The published [hook tests](../../hook-tests/) also exercise expansion syntax against Bash with inert command stubs, then check the guard verdict. Run `python3 tools/claude/examples/hook-tests/test-expansion-semantics.py` from the repository root. Its selected fixture scripts execute with a temporary-only `PATH`, controlled startup files, and temporary working directories; the corpus must still be reviewed before execution.

When you add a rule, add the case *and* mutation-test it: revert the rule, confirm the new case goes red, restore, and check the file is byte-identical again. A case that stays green with the rule removed is testing nothing.

**Mutation-testing the fix is not the same as testing what the fix widened.** A change to `strip_cmd`'s heredoc pattern once passed its own mutation test — the new case went red without it — while that same widening silently disabled every rule in this file for any command prefixed with `cat <<EOF;`. The suite stayed green because all 77 cases at the time were canonically formatted. When a change makes a matcher *more* permissive, the case you owe is the one proving it did not become permissive somewhere else; that is what the adversarial-formatting cases (heredoc marker lines, tabs, line continuations) are for.

## Customization

Move patterns between tiers based on your risk tolerance:

```bash
# Move terraform destroy to hard block (no approval possible)
HARD_REASON="terraform destroy — blocked unconditionally."

# Move git stash drop to soft block (user can approve)
SOFT_REASON="git stash drop — permanently discards stashed changes."
```

Add patterns for your stack:

```bash
# Docker — soft block
if echo "$CMD" | grep -qE 'docker +(rm|rmi|system +prune)'; then
  SOFT_REASON="docker cleanup — removes containers or images."
fi

# Database CLI — hard block
if echo "$CMD" | grep -qE '(psql|mysql|mongo).*DROP +(DATABASE|TABLE)'; then
  HARD_REASON="database DROP — irreversible schema destruction."
fi
```

## Why Two Tiers?

A single `exit 2` for everything is too strict — it blocks operations the user explicitly asked for (like creating a PR) with no way to approve. A single `ask` prompt for everything is too weak — one keystroke in the permission prompt approves an operation that should never be approvable mid-session (like deleting an RDS instance).

The two-tier approach gives you both: unconditional safety for irreversible operations, and a confirmation prompt for everything else.

## Companion Hooks

- **[`stateful-op-reminder`](../stateful-op-reminder/)** — Nudges (does not block) when detecting mutations to external systems. Catches plausible-looking API calls that destructive-guard can't pattern-match.
- **[`pr-create-guard`](../pr-create-guard/)** — Verifies pre-creation conditions before allowing `gh pr create`.
