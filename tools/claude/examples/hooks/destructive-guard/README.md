# Destructive Operation Guard

PreToolUse hook with two-tier blocking for destructive operations.

## Two-Tier Design

| Tier | Mechanism | Override by `Bash(*)`? | Use for |
|------|-----------|------------------------|---------|
| **Hard block** | `exit 2` + stderr | No — always blocks | Irreversible data loss and forbidden PR ops (AWS deletions, push/force-push to main, PR close, a merge nobody asked for) |
| **Soft block** | JSON `permissionDecision: ask` + `exit 0` | Yes — user can approve | Risky but approvable (PR create, force-push to a branch, terraform destroy) |

Hard blocks stop the tool call unconditionally — no override is possible. The user must run the command themselves in their terminal.

Soft blocks emit `permissionDecision: ask` JSON on stdout and exit 0. Claude Code shows the reason in a permission prompt where the user can approve or deny — even when `Bash(*)` is in the allow list.

## What It Blocks

### Hard Blocks (irreversible)

| Pattern | Why |
|---------|-----|
| `git push` to main/master — any refspec in the push, or a bare push from a checkout of it | Must go through PRs |
| `git push --force` to main/master | Rewrites shared history on default branch |
| `git push --all`, `--mirror`, `--branches` | Pushes every local branch, main included |
| A bare `git push` from a directory the command names by a variable or a multi-word quoted path | The branch it pushes cannot be read from the text; naming it (`git push origin <branch>`) clears the block |
| `gh pr close` | Loses PR context — never without explicit user instruction |
| `gh pr merge`, `gh api .../pulls/N/merge`, `gh api graphql` `mergePullRequest`, `gh stack merge` | One gate for all four forms: no approval path unless the user's latest prompt asked for a merge — see [Merges](#merges) |
| `gh pr merge --admin`, also through a variable | Bypasses branch protection and required checks — hard whether or not a merge was asked for |
| `git clean -f` | Permanently deletes untracked files |
| `git stash drop/clear` | Permanently discards stashed changes |
| Bulk `git branch -d/-D` (xargs, loop, or several names) | One bad glob wipes hundreds of refs |
| `aws * delete-*`, `aws s3 rm`, `aws ec2 terminate-*` | Cloud resource destruction |
| `aws dynamodb delete-table`, `aws kms schedule-key-deletion`, and peers | Destroys stored data, its backups, or the key that decrypts it |

### Soft Blocks (confirm first)

| Pattern | Why |
|---------|-----|
| `gh pr create` | Visible shared action; no prompt in a turn whose prompt asked for a PR ([`merge-grant`](../merge-grant/)) |
| `gh stack submit/link/unstack` | Acts on every PR in the stack, not one |
| `gh issue <mutating verb>`, `gh api .../issues` with a method or field | Files an external artifact under your GitHub identity |
| `gh run delete` | Permanently removes CI run history |
| `git push --force`/`-f`/`+refspec` to a non-default branch | History rewriting (reversible via reflog); an exact lease on your own PR runs unprompted ([Own-PR lease](#own-pr-lease)) |
| `git push --delete` / `git push origin :branch` | Deletes a remote branch, auto-closing any PR on it |
| `git reset --hard` | Discards uncommitted changes (recoverable via reflog) |
| `git branch -D` (single), `git checkout --` (the bare `--`, not a long option), `git restore` | Discards local changes |
| `terraform destroy/state rm/force-unlock/workspace delete` | Infrastructure changes |
| `kubectl delete/drain/cordon/scale/rollout undo/patch` | Live cluster mutations |
| `helm uninstall/rollback` | Release changes |
| Any `aws <service> delete-*` / `remove-*` / `terminate-*` / `purge-*` / `deregister-*` / `destroy-*` | Default-deny for the whole destructive verb family |

## Worktree-Aware Push Detection

The guard correctly handles worktree-based workflows where the repo root stays on `main`:

- `cd /tmp/worktree && git push` — detects the `cd` and checks the branch in the target directory, not the hook's CWD; a `-C` on the push itself wins over the `cd`, and a `cd` inside `( … )` stays inside it
- `git push origin feature-branch` — recognizes a named non-main branch is safe
- `git push origin local:remote` — recognizes explicit refspecs are safe (unless pushing TO main)
- `git push origin feature:main` — correctly blocks pushing to main via refspec

This prevents false positives when the hook's working directory is on `main` but the push targets a feature branch in a worktree.

## Parser hardening

Every rule here is a regex over command *text*, so the parser is where this hook fails silently rather than loudly. These habits keep it honest — each one is a fix for a miss that was reproduced, not imagined:

- **Expand `~` and `$HOME` in an extracted path.** A path lifted out of the command string is never shell-expanded, so `cd ~/repo && git push` leaves `~/repo` literal, `git -C '~/repo'` fails, the branch reads empty, and empty is not `main` — the push to `main` sails through. Whichever way the lookup is wired, an unresolved path **fails open**. `expand_path` resolves `~`, `~/…`, `$HOME` and `${HOME}` before any lookup.
- **Match a token, not a substring.** Extracting `push[^;&|]*` finds its first hit inside `git -C /tmp/x-push-y push origin main` — in the *path* — so the ref parsed out is `origin` and the guard stays quiet on a push to `main`. `push_args` walks whitespace-separated tokens and starts after git's subcommand when that is `push`: the first word after `git` that is not a global option or its value (`-C <dir>`, `-c <name>=<value>`, `--git-dir <dir>`, `--attr-source <tree-ish>`, `--shallow-file <file>`, `--no-pager`). One list of the options that take a separate value serves the regex and the token walk, so the two cannot disagree. So `git stash push`, `git log --grep push` and `git -C <repo> grep -n checkout` are not a push or a branch switch, the soft delete and force prompts included, and a `push"` or `push'` that closes a shell string has no arguments: the words after the string are that shell's `$0`, `$1`, … (`bash -c "git push" origin feature`).
- **Isolate separators before tokenising.** A token walk splits on whitespace, so `git push origin main;echo done` makes `main;` a single field. Dropping that field for containing a separator drops the ref with it, and the push to `main` reads as ref-less. `push_args` spaces out `;`, `&` and `|` first, so the ref survives and only the separator ends the scan. The force and delete checks read the same spaced view: a flag glued to a separator (`-f;echo ok`, `--force&&…`, `--delete;`) never met their end-of-word test and ran with no prompt.
- **Drop redirections, with their targets, before either.** `git push>/dev/null origin main` never matched `push` followed by whitespace, and the `&` in `2>&1` or `&>/dev/null` ended the token walk before the refspec: both pushes to `main` ran unchecked, and `git push 2>&1 -f origin feature` ran without its force prompt. `strip_redirs` removes every redirection operator and its target first.
- **Read every refspec, and skip the option values that are not one.** Taking the second non-option word as *the* ref missed `main` in `git push origin feature main`, read `ci.skip` as the remote in `git push -o ci.skip origin main`, and saw nothing at all in `git push --all`. `push_hits_main` skips the values of `-o`, `--push-option`, `--repo`, `--receive-pack`, `--exec` and `--recurse-submodules` — every `git push` option whose value can be the next word — checks the destination of every refspec — a glob destination counts as `main` — and blocks `--all`, `--mirror` and `--branches` outright. It reads an option the way git does: any unique prefix of a long option names it (`--recu`, `--mirr`, `--al`), and in a bundle of short flags the first `o` takes the rest of the word, or the next word when it comes last (`-uo ci.skip`, but `-oo origin main` names the remote). The matching refspec `:` (or `+:`) pushes every branch that exists on both sides, so it blocks like `--all`. `--tags` with no refspec pushes tags only, so it defaults no branch in. An unquoted substitution where the remote goes can expand to no word at all, which makes the push bare, so it also stands for the checked-out branch; a quoted one is always one word, so it is only the remote. The delete check reads a `:branch` refspec in any position, not only right after the remote, and `-d` abbreviated or bundled (`--del`, `-qd`); the force check reads any `+refspec` (`+HEAD~1:feature` included) and an abbreviated `--force-with-lease` (`--force-w`).
- **Extract from the *stripped* command.** Ref extraction on the raw command lets a bare `push` inside a `-m` message synthesise a ref: `git commit -m "fix push for main branch" && git push origin feature-x` parsed `main` out of the message and hard-blocked ordinary feature work, with no approval path.
- **`HEAD` is not a ref name.** `git push origin HEAD` pushes whatever branch is checked out, so treating `HEAD` as an explicit ref skips the branch lookup entirely and misses a push to `main`. It is cleared so the lookup runs.
- **An unreadable destination is the checked-out branch.** `git push origin $(git branch --show-current)` and `git push origin "$B"` name their branch at run time, and reading `SUBSTITUTION` or `$B` as a branch called that let the first one push `main` from a checkout of `main`. A destination the text cannot read is resolved like `HEAD`, which is what the common idiom means. A variable that holds `main` while a feature branch is checked out still passes: the text cannot see its value.
- **Evaluate the push rule per segment, not once per command.** `push_args` used to start at the first token equal to `push`, so a bare `push` anywhere earlier — in an `echo`, a `grep`, a PR body — captured the extraction and left the real `git push origin main` behind it completely unguarded. The rule now walks each segment that carries a `git … push` and blocks on the first that targets the default branch.
- **Unquote every extracted value, not most of them.** The push directory and `CMD_TARGET` were unquoted and the push ref was not, so `git push origin "main"` compared `"main"` against `main` and passed. A partially-applied normalisation reads as done.
- **Extract a loop body; don't match across it.** A greedy `.*` before `do` anchors on the *last* one, so a second loop — or a later sentence containing the word `do` — replaced the real body and disarmed the rule. Non-greedy, and repeated over every `do…done` pair.
- **Resolve the working directory per segment, tracking `cd` as the shell does.** The branch-switch check took the first `-C` anywhere in the command, so `git -C <other-repo> log && git checkout main` resolved against the repo the *read* named; the push check took the *last* `cd` anywhere and preferred it over the push's own `-C`, so `cd <feature-repo> && git -C <main-repo> push` read the wrong branch. Both checks now share one walk, `resolve_segment_dirs`: a `cd` moves the directory for every later segment in its scope unless it runs in a pipeline component or as a background job (`cd <dir> | true`, `cd <dir> &`), both subshells, leaving a `( … )` or a `$( … )` restores the parent's directory and exported `GIT_DIR`, and a `-C` binds only to its own invocation, resolved against the directory its segment runs in — which also stops one `git checkout -- .` from disarming a real cross-repo checkout beside it. A `cd` counts behind a reserved word or a builtin prefix (`if cd <dir>; then`, `do cd`, `builtin cd`, `command cd`, `time cd`) and inside a `case` arm; `pushd <dir>` moves like `cd`, `pushd -n` does not move, `popd` leaves a directory the text cannot name, and a `cd` with only options goes home, as the shell's does. Only an unbalanced, unescaped `)` closes a subshell, so the pair in `$((1+1))`, an escaped `\)` a `case` pattern's `)` (`x)` or `x )`), a `)` inside a quoted shell string and a `|` inside a `[[ … ]]` that closes later do not pop a `cd` early; an unmatched `[[` is a plain word. A pattern is read only at the subshell depth its `case` opened at, so a subshell's last word (`(cd <dir>; true)`) and `esac)` still close it. `--git-dir` and `GIT_DIR=` name the repository and resolve like a `-C` after any other; a linked worktree's `.git` file names that worktree, and a named repository that does not exist is unresolvable. An exported `GIT_DIR` (`export GIT_DIR=<dir> && …`, or `declare`/`typeset`/`local` with any flag bundle holding `x`) does the same for every later git command that names none of its own, resolved where that command runs as git resolves a relative one, until `unset GIT_DIR`. `--work-tree` and `GIT_WORK_TREE` leave the repository where it was. A directory named by a variable, a command substitution, a multi-word quoted path or a backslash-escaped one is unresolvable. So is the repository after a bare `GIT_DIR=<dir>` assignment or an `export GIT_DIR` with no value, since either reaches git only through an export the text may not show. The same holds for the directory of a push inside a shell string (`bash -c "…"`, `eval "…"`, `ssh <host> "…"`, or one that `xargs`, `timeout` or another wrapper hands to a shell), where a `cd` is not followed; every command in the string is checked, not only the first push, with one level of escaped quotes decoded (`bash -c "git push origin \"main\""`), also when an escaped quote around an option value hides the push from the segment's own text (`bash -c "git -C \"my dir\" push …"`). A line continuation in the string is joined first, a string spelled in chunks with `'\''` or `"\""` is one string, and `bash -c -- '…'`, `fish -c` and `busybox sh -c` run their string too. An `eval` runs in this shell, so a `cd` or `GIT_DIR` inside one makes every later segment unresolvable. A bare push through an `xargs` anywhere before `git` (its refspec can come from stdin), a destination built from an `xargs` replace string (`-I`, `-i`, `-J`, `--replace`), and a bare push under a config key that picks what it sends are unresolvable too. The keys are `remote.<name>.push`, `remote.<name>.mirror`, and `push.default` with any value but `simple`, `current` or `nothing`; they are read case-insensitively, as git reads them, and through `--config-env`, `GIT_CONFIG_COUNT` or `GIT_CONFIG_PARAMETERS`. A bare push from any of them blocks until the branch is named. A bare push reads the branches an earlier move in the same command may leave in its checkout, not the branch checked out when the hook runs. The moves are `git checkout <branch>`, `checkout -b|-B`, `checkout --track <remote>/<branch>`, `switch [-c|-C]`, `branch -m`, `worktree add`, `symbolic-ref HEAD <ref>` and `rebase <upstream> <branch>`, with glued values (`-Bmain`, `--create=x`) and a `--` before the name. A move counts as done only for a push in its `&&` chain; `then` or `do` after a condition that is not negated, and `<move> || exit; <push>`, count as `&&`. After a `;`, `||`, `|`, `&` or newline the move may have failed, so the push may send the move's branch or the one before it, and it blocks if either is main. So `git checkout main && git push` blocks, `git checkout -b x && git push -u origin HEAD` from main passes, and `git checkout -b x; git push -u origin HEAD` from main blocks: an existing `x` fails the create, and the push sends main. `checkout -`, `--detach`, a target the text cannot read (a variable, a substitution, `@{-N}`), a move in a directory the text cannot name, and a move anywhere in the loop body the push repeats in leave it unresolvable. A checkout with paths after it, after `--` or from `--pathspec-from-file` moves nothing. Moves and pushes are matched by the worktree's own git dir, so a push through `--git-dir=<repo>/.git` sees a move made in the work tree. A push from a directory that does not exist at hook time is unresolvable, after a `;` as well: either the command makes the directory, and `git clone <url> d; cd d; git push` sends the clone's default branch, or the `cd` fails and the push runs where the shell was. `$(git rev-parse --show-toplevel)` with no `-C`, optionally with `2>/dev/null` or `2>&1` (a space after `2>` too), is the one substitution read when it starts a word: it is the top of the checkout the shell is in, and the rest of the word follows it, inside its quotes or after them (`"$(…)"/sub`), so `cd "$(git rev-parse --show-toplevel)" && git push` reads that checkout's branch and `cd $(git rev-parse --show-toplevel)/../other && git push` reads the sibling's. After a `-C` chain, as a `--git-dir=` or `GIT_DIR=` value, and in a quoted `export GIT_DIR="$(…)/.git"`, it still resolves in the shell's directory, where the substitution runs. Any other, `$(git -C <dir> rev-parse --show-toplevel)` included, stays unresolvable.
- **Scope a negative test to one segment.** A `! grep` over the whole command line is satisfiable by *any* segment, so `gh api -X GET …/labels && gh api …/issues -f title=x` had its own read disarm the gate for the mutation beside it. `seg_matches` splits on unquoted separators first (via `_lib/split-cmd-segments.pl`) and requires the positives and the absence of the negative to hold within one segment. If the splitter is unreadable it falls back to whole-command matching — the behaviour it replaced, rather than silence.
- **Confine a flag test to the segment that owns it.** Scanning the whole command line for a force flag fires on an unrelated `rm -f` after the push; scanning only the first `push` misses `git push origin a && git push --force origin b`. The `PUSH_SEG` prefix (`push[^|;&]*`) does neither: `grep` still finds a later push, and no match can cross `|`, `;` or `&`.
- **Normalize whitespace with its quote context.** Inter-token tabs become spaces and escaped newlines are removed by the quote helper. Quoted data keeps its original characters in the extraction view.
- **Fail closed on preprocessing errors.** The hook checks `jq` and `perl` at entry and exits 2 with a named reason if either is absent. A missing quote helper or detected parse error also blocks, before an empty result can reach the fast-path gate.
- **Derive matching and extraction views from the original syntax.** `_lib/strip-quoted-args.pl --values` retains argument values in `CMD_STRIPPED`; the default mode blanks multi-word quoted data in `CMD_MATCH`. Both unquote parsed simple tokens such as `"gh"`, so quoted executables still match. Each nested substitution has its own quote context: the quotes inside `"$(printf "$(printf path)")"` cannot consume a later command. Static payloads handed to recognized shells remain visible.
- **Descend into command substitutions.** `$()` and backticks execute before their surrounding command, including inside double quotes and arithmetic expansion. The quote helper decodes legacy backticks one level at a time and renders them as `$()`. The splitter emits inner commands separately without closing delimiters, so a push to `main)` is identified as a push to `main`, and a process substitution (`<(…)`, `>(…)`) is descended into the same way. Single-quoted and escaped spellings stay literal. Checkout and push use a typed scoped pass to restore their directory after a substitution; that pass keeps the enclosing command whole around it, because cutting `git -C "$(…)" push` at the substitution left one half with `git` and the other with `push`, and neither was checked.
- **Keep executable heredoc expansions.** An ordinary unquoted heredoc can execute `$()` and backticks even when its body looks like quoted prose. The helper preserves these expansions while discarding literal body text, consumes multiple bodies in order, and resumes at the command after each terminator. Quoting any part of the delimiter disables expansion. Interpreter classification belongs to the command receiving that body: an earlier shell command cannot turn a later `cat` body into code, and tested shell wrappers still preserve executable stdin. Script and inline-command modes retain stdin as data. Tests cover mixed quoting, `<<-`, continuations, and here-strings.

This remains a targeted command-surface detector, not full Bash grammar or an execution sandbox. Commands assembled dynamically through variables are not resolved, and the code in an `eval` or `bash -c` string is read as text: every push in it is checked, but a `cd` in it is not followed (after an `eval`, the directory is unresolvable). Comment text is inspected conservatively in an isolated segment. Detected parse errors can therefore block unsupported syntax as well as malformed commands.

Three related defaults: a target that is not a git repository never counts as a cross-repo branch switch (without that test, every `cd <non-repo> && git checkout` blocked); the branch-switch check compares repositories by physical path, so a symlinked parent (macOS `/var` is `/private/var`) cannot make one repository read as two; and a push directory that exists but is not a repository falls back to the session's own branch rather than to an empty string — a failed `cd` into it does not stop a `;`-chained push, which then runs in the session's directory. A push directory that does not exist is unresolvable instead, as described above.

## Why `--dry-run` is not exempt

`git clean -fdn` previews rather than deletes, so exempting it looks free. It is not: the exemption is a second `grep` over the same command line, and `git clean -fdn && git clean -fd` satisfies it in the first segment while the second segment does the real delete. The block would then be lifted for the destructive half.

The same argument applies to `git push --dry-run origin main`, which is likewise blocked. In both cases the cost of the false positive is one command the user runs themselves; the cost of the fail-open is the thing the hook exists to prevent. A per-segment exemption would be sound, but it is strictly more machinery than the false positive is worth.

## Bulk branch deletion

Deleting one branch is a soft ask: a branch is a ref, and the reflog holds the tip for `gc.reflogExpire` (90 days by default), so it is recoverable.

Bulk deletion is a hard block in three shapes — `xargs`, a `for`/`while` loop, and several branch names in one command. What changes is not the delete but the blast radius: a glob that matches more than intended wipes hundreds of refs in one call, and no reflog makes that reviewable afterwards. Both `-d` and `-D` are blocked in the bulk forms, and the message says so, because a message naming only `-D` invites a retry with `-d` that fails the same way.

The loop form **extracts the body between `do` and `done`** rather than matching across it. Matching across fails in both directions: a multi-line body puts arbitrarily many separators between the loop header and the delete, so a real bulk delete written over three lines matched nothing, while `for x in a b; do echo $x; done && git branch -D one` matched and hard-blocked a single delete that was never in the loop.

## Merges

The four merge forms share one gate, and each hard-block message names all four, because a reader who trips one retries with another. On its own this hook hard-blocks all of them. The GraphQL form carries its mutation in quoted data or a heredoc body, both of which the parsed views drop, so that rule reads `mergePullRequest` and `enablePullRequestAutoMerge` from the raw command; a mutation in a `--input` or `-F query=@file` payload never reaches the hook as text.

Installed with [`merge-grant`](../merge-grant/), a merge becomes a permission prompt in exactly one case: the user's latest prompt asked for it. The prompt quotes that request so the approver can check the PR is one it names. The grant lasts until the user's next prompt, is scoped to its session, and every unusable state — no session id, an expired or unparseable grant, one written for another session — falls back to the hard block. `gh stack merge` says in its prompt that every layer beneath the target must be one the user named, since it lands all of them.

A grant never lifts a hard block raised by anything else in the same command: `gh pr merge --admin` — checked on the values view, so `F=--admin; gh pr merge 17 $F` counts — or a merge chained with `git clean -f` still exits 2.

## Own-PR lease

A force-push to your own PR branch is routine — a rebase, a squash, an amended commit — and a prompt on every one of them trains the approver to click through. The prompt exists to protect *someone else's* commits on the remote, so one exact shape runs without it, `git push origin <branch> --force-with-lease=<branch>:<sha>`, and only when all of these hold:

| Condition | Why |
|---|---|
| The whole command is that one push, typed as a simple command: `git push …` or `git -C <dir> push …`, with no separator, newline, redirect, subshell, `$`, backtick, quote, backslash, glob, brace, `#`, leading assignment or `git -c` | Clearing the prompt must not also clear one a second push raised, and a redirect such as `&>/dev/null +main` hides a second refspec from a token walk |
| Its remote is `origin` and it names one plain branch — not `main`/`master`, `HEAD`, a `src:dst` refspec, a `refs/` path or a `+branch` | A wider refspec overwrites more than the lease protects |
| The only force flag is `--force-with-lease=<branch>:<sha>` for that same branch, with a 7–40 hex SHA; besides it only `-u`/`--set-upstream`, `--force-if-includes`, `-q` and `-v` | `--force`, `-f`, a bare `--force-with-lease`, a lease without a SHA, and any other flag (`--mirror`, `--all`, …) keep the prompt |
| Every commit between the default branch and `<sha>` has your `git config user.email` as its author | The lease overwrites exactly `<sha>`; a collaborator's commit under it is work the push destroys |
| `origin`'s push URL is a GitHub URL, the branch has at least one open PR from that same repository, and every such PR was opened by the account `gh` is logged in as | "Your own PR" is read from GitHub, not inferred from the branch name. The push URL, because a `pushurl` or `pushInsteadOf` sends the push somewhere the fetch URL does not name; same-repository, because a fork's PR from a branch with the same name is not this branch's PR |

Every lookup fails closed. A missing commit, no `origin/main` or `origin/master`, a non-GitHub remote, a missing `gh`, `perl` or `../_lib/pr-author.sh`, no open PR, PRs from more than one author, or `PR_AUTHOR_LOOKUP=0` leaves the prompt in place, and so does a `gh` call that outlives `PR_AUTHOR_TIMEOUT` seconds (default 8): a `PreToolUse` hook that times out lets its tool run, so each call is bounded rather than left to the hook timeout. The prompt names the exempt shape and says it must be the whole command (`git -C <dir> push …`, not `cd <dir> && git push …`), so an agent that trips it learns the form that does not need a human.

The author check reads `git config user.email`, which anyone can set. It is a guard against overwriting a collaborator by accident, not against an agent that sets out to forge authorship.

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
            "command": "$HOME/.claude/hooks/destructive-guard/destructive-guard.sh"
          }
        ]
      }
    ]
  }
}
```

Requires `jq` and `perl` on PATH, plus `../_lib/hook-diag.sh`, `../_lib/strip-quoted-args.pl`, and `../_lib/split-cmd-segments.pl` installed under the same parent directory as the hook. The [own-PR lease](#own-pr-lease) also needs `../_lib/pr-author.sh` and an authenticated `gh`; without them that push asks, as every other force-push does. Update the guard and helpers together. To let the agent merge, or open a PR without a second prompt, when the user asks, also register [`merge-grant`](../merge-grant/); the guard reads its store from `$CLAUDE_MERGE_GRANT_DIR` (default `~/.claude/merge-grants`).

## Testing

The repo's own copy of this hook is covered by `.claude/evals/destructive-guard/cases.json`, run by `.claude/evals/runner.py`. Cases assert an exit code and a substring, on the combined output (`expected_output`) or on one channel (`expected_stdout` / `expected_stderr`) when the channel is the behaviour under test.

Cases whose behaviour depends on real git state carry `setup`/`cleanup` shell snippets — branch detection cannot be exercised without a repository to detect a branch in. A failing `setup` fails the case rather than letting it pass against a fixture that was never created.

The published [hook tests](../../hook-tests/) also exercise expansion syntax against Bash with inert command stubs, then check the guard verdict. Run `python3 tools/claude/examples/hook-tests/test-expansion-semantics.py` from the repository root. Its selected fixture scripts execute with a temporary-only `PATH`, controlled startup files, and temporary working directories; the corpus must still be reviewed before execution.

The own-PR lease reads live state — the commits under the lease and the PR's author — so `tools/claude/examples/hook-tests/test-force-push-lease.py` builds it per case: a real repository whose `origin` is a GitHub URL and a `gh` stub on `PATH`. Every `allow` case there answers `ask` with the predicate disabled.

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
- **[`merge-grant`](../merge-grant/)** — Turns a merge into a permission prompt, and drops the `gh pr create` prompt, for the one turn whose prompt asked for it.
