# `_lib/` — shared utilities for hook authors

This directory holds shell utilities that other hooks source. The leading underscore signals "infrastructure, not a hook itself" — the loader doesn't try to register `_lib/*.sh` as hooks.

## What's here

| File | Purpose |
|------|---------|
| [`strip-cmd.sh`](strip-cmd.sh) | `strip_cmd "$CMD"` blanks heredoc bodies and `-m`/`--message` contents; `strip_quoted_args "$CMD"` blanks quoted literals. Both keep pattern matching on the command surface rather than on text a command carries. |
| [`hook-diag.sh`](hook-diag.sh) | Diagnostic wrapper. Sourced AFTER reading stdin into `$INPUT`. Logs closed metadata to rotating JSON Lines files, re-emits captured stderr on exit 1 and exit 2 so the reason reaches the model, and records a hook that wrote to stderr on exit 0 — where the harness discards it. |
| [`strip-quoted-args.pl`](strip-quoted-args.pl) | Reads raw shell text on stdin and preserves executable expansions while blanking quoted data; `--values` retains argument values for extraction. |
| [`split-cmd-segments.pl`](split-cmd-segments.pl) | Splits executable shell segments and recognised command substitutions into NUL-delimited records. |
| [`resolve-workdir.sh`](resolve-workdir.sh) | `resolve_workdir "$CMD"` returns the repository a git command acts on — via `git -C <dir>` or a leading `cd <dir> &&` — or nothing. |
| [`pr-author.sh`](pr-author.sh) | Cached predicates for PR authorship and repository visibility, for gates that treat a self- or bot-authored PR differently from someone else's. |

## Why these exist

### `strip-cmd.sh`

`grep -qE 'gh +pr +close'` will hit on a commit message that contains the words "gh pr close" — typically when the model writes a heredoc explaining what NOT to do. `strip_cmd` removes the heredoc body before matching, so guard patterns only fire on the actual command surface.

The heredoc pattern deliberately allows text between the delimiter word and the newline. `cat <<EOF > notes.txt` puts a redirect there, and a pattern requiring only whitespace leaves that whole body unstripped — the case where a body is most likely to contain command-looking prose.

**But that class must exclude command boundaries**, and getting this wrong is a total bypass rather than a missed strip. With a permissive `[^\n]*`, the marker line's match runs past a `;` or `&&` and swallows *the next command with it* — so `cat <<EOF; git push origin main` deletes the push from the text every guard pattern then examines, and bash runs it anyway as a separate command. The class is therefore `[^\n;&|(` + backtick + `]*`: a redirect still strips, while `;`, `&`, `|`, `(` and a backtick each stop the match and leave the following command visible. Over-stripping here disables every rule at once, so the failure is silent and total; under-stripping merely over-fires.

`strip_cmd` also returns its input **unchanged** when `perl` is unavailable, rather than empty. An empty result would make every downstream `grep` match nothing, which reads as "no dangerous pattern found" — a guard that silently stops guarding.

`strip_cmd` asks the quote helper which heredoc bodies are code (`--bodies`, below), so it keeps the same bodies the destructive guard reads: `sudo sh <<EOF`, `cat <<EOF | ( cd x; sh )` and the rest. When the helper is missing or cannot parse the command, the older interpreter-name test decides instead. A double-quoted `-m` message is kept only when it holds a live `$(` or backtick; an escaped one is text, so the message strips.

`strip_quoted_args` turns `strip_cmd`'s `<<STRIPPED_HEREDOC>>` placeholder into a plain word before calling the quote helper. The helper parses heredocs, so it would read the placeholder as a new opener whose body runs to the end of the command, and a caller chaining the two (`strip_quoted_args "$(strip_cmd "$CMD")"`) would see nothing after the first heredoc.

### `strip-quoted-args.pl`

`git grep -rn 'git checkout main' .` is a search, and a detector looking for a *command invocation* must not fire on it. The destructive guard passes the original command directly to this helper in two modes: default matching blanks multi-word quoted data, while `--values` retains it for path extraction. A third mode, `--bodies`, serves `strip_cmd`: it prints the command as written, with each data heredoc's opener replaced by `<<STRIPPED_HEREDOC>>` and its body removed, code bodies left in place, and one line appended for each piece of code the raw text does not show as a command, such as a here-string fed to a shell or the command an exec call in a Python body runs. Both modes unquote parsed simple tokens such as `"git"` and preserve nested expansions. Applying a quote regex or `strip_cmd` first loses syntax this helper needs.

Two kinds of quoted span survive blanking: command substitutions and payloads handed to a shell (`bash -c "…"`, `eval "…"`, `ssh host "…"`). A wrapper that runs its operands as a command (`xargs`, `timeout`, `gtimeout`, `nice`, `nohup`, `sudo`, `doas`, `stdbuf`, `setsid`, `ionice`, `find -exec`, `caffeinate`, `arch`, `script`, `runuser`, `chroot`, `unbuffer`, `chrt`, `taskset`, `busybox`) is looked through to the shell or `ssh` after it, so `xargs -I{} sh -c "…"` keeps its payload. The shells are `bash`, `sh`, `zsh`, `ksh`, `mksh`, `pdksh`, `oksh`, `loksh`, `lksh`, `dash`, `ash`, `posh`, `yash`, `csh`, `tcsh` and `fish`, and a `--` between `-c` and the string still marks it as code. The quoted chunks of one word share its verdict, so `bash -c 'a '\''b'\'' c'` is kept whole, not read as a kept chunk followed by data. Commands that hand their own string operand to a shell keep it too: `su -c` (or `--command=`), `flock <file> -c`, `watch` and `parallel`. A quoted chunk with no space or shell syntax next to a substitution stays readable (`"$(…)/sub"`), since it cannot form a command phrase. Each substitution has its own quote context, so nested quotes cannot consume a later command. Empty quote fragments, escaped ordinary letters, and supported ANSI-C escapes are normalized before token matching. Legacy backticks are decoded one level at a time and rendered as `$()` before segment splitting.

Heredoc bodies are consumed in redirection order. For ordinary commands, quoted delimiters suppress expansion; unquoted delimiters retain command substitutions, including those inside arithmetic expressions. Mixed delimiter quoting, `<<-` tab stripping, backslash-newline joining, and commands after the terminator are covered by Bash-oracle fixtures. Interpreter classification uses the command owning each redirection, including its later arguments and tested assignment, `command`, `env`, `exec`, `time`, and `!` prefixes, and, when that command pipes its output on (`|` or `|&`, not `||`), every later command in the pipeline, so `cat <<EOF | sh` is code and `cat <<EOF | grep x` is data. Shell stdin mode preserves code; script and `-c` modes leave stdin as data. Common language-interpreter file/inline modes also leave stdin as data, while SSH input is inspected conservatively. An exec wrapper (`sudo`, `timeout`, `nohup`, `nice`, `doas`, `stdbuf` and the rest of the list above except `xargs`, `find` and `script`) hands its stdin to the interpreter it runs, so `cat <<EOF | sudo sh` and `sudo -u x bash <<EOF` are code.

Groups follow the same rule. A `( … )` or `{ …; }` opened at the start of a pipeline component, after any reserved words (`!`, `time`, `if`, `while`, `then`, `do`), gets the pipe as its stdin, and that stdin reaches every command inside, so `cat <<EOF | ( cd x; sh )` is code. A group's output is every command's in it, so `(cat <<EOF) | sh`, `! (cat <<EOF) | sh`, `( { cat <<EOF; } ) | sh` and `{ echo x; cat <<EOF; } | bash` are code, while `(cat <<EOF) > notes.md` is data. An output process substitution reads what its command writes, so `cat <<EOF > >(sh)` and `| tee >(sh)` are code. A pipeline continues past the newline after a trailing `|` and past the heredoc bodies that newline starts, so `cat <<EOF |`, the body, then `sh` on the line after the terminator is code.

A heredoc inside a substitution is code when the substitution's output is: under `eval`, `sh -c`, `ssh` or another payload-taking command (`eval "$(cat <<EOF …)"`), at command position or after an exec wrapper (`$(cat <<EOF …)`, `sudo $(…)`, but not `X=$(cat <<EOF …)`), or when the command it is an argument of pipes into an interpreter (`echo "$(cat <<EOF …)" | sh`). An argument is never its command's stdin, so `bash -s -- "$(cat <<EOF …)"` passes data. A process substitution is code when the command reads it as a script: `source <(…)`, `. <(…)`, a shell or a language interpreter; `diff <(…) other` is data. A here-string is its command's stdin, like a heredoc body, so the same rules decide whether it is code (`bash <<< "…"`, `cat <<< "…" | sh`); it is read as one word however it is quoted (`git' push'`, `git\ push`, `'git'" push"`), and a substitution in it stays visible wherever it runs.

Some of these verdicts arrive after the body has been rendered: the `sh` after the terminator, the `| sh` after a substitution. A heredoc marked as code after its body was rendered records its id (its context and offset), and the scan runs again with that heredoc treated as code from the start, until a pass marks nothing new.

A Python, Perl, Ruby or Node body is not shell, and neither is the string after `python3 -c`, `perl -e`, `ruby -e` or `node -e`. Each is still scanned as shell, which reads Perl and Ruby backticks. When that parse fails, as it does on a stray apostrophe, a body that can start a process (`subprocess`, `system(`, `exec…(`, `spawn…(`, `popen(`, `Open3`, `child_process`, `qx`, `%x`) fails closed, because its commands cannot be read; any other body is allowed, with its backtick spans and, for an unquoted delimiter, its expansions scanned instead. In every such body, the string arguments of an exec-style call are joined and read as a command: `os.system`, `os.popen`, `os.exec*`, `os.spawn*`, `subprocess.*`, `Popen`, `check_output`, `check_call`, `system`, `exec`, `execSync`, `execFileSync`, `execFile`, `spawnSync` and `spawn`, with a list argument read word by word, keyword or not (`subprocess.run(args=["git", "push", …])`), plus Perl `qx` and Ruby `%x` with any delimiter, bracket pairs nesting. When the body parses as shell, a string printed or assigned is not read, and an argument built from variables is not resolved. These rules follow the Bash manual's [command substitution](https://www.gnu.org/software/bash/manual/html_node/Command-Substitution.html) and [redirection](https://www.gnu.org/software/bash/manual/html_node/Redirections.html) semantics for the tested forms.

Missing helpers and detected parse errors make the destructive guard exit 2. Unsupported ANSI-C escapes and substitution-shaped heredoc delimiters also block. This is a targeted detector, not full Bash grammar or an execution sandbox: dynamic command construction is not resolved, a script written to a file and run later is not read, and an interpreter payload is read only through the exec calls above. Comment text is inspected conservatively in a separate segment, so a comment's quoting or flags cannot hide the next executable command.

Use it only for detectors matching an invocation. A detector matching *content* — a URL, a SQL statement — must run on the unstripped command, since that content is legitimately quoted.

### `split-cmd-segments.pl`

A flag test written against the whole command line answers for the wrong command. `gh pr list --json url | jq -r 'select(.state)'` carries a `select` belonging to `jq`; an allowlist keyed on `gh` flags cannot tell. Splitting first lets each detector run against the segment that owns what it is testing.

Segments are NUL-delimited because a segment may itself contain newlines — a quoted multi-line body — so a newline-delimited stream cannot be read back into whole segments. The splitter recursively emits tested `$()` nesting and simple backtick substitutions without their delimiters. Single-quoted and escaped spellings remain data, while substitutions in double quotes remain executable.

This is a targeted command-surface parser, not a Bash interpreter. Its tested scope is separators, single and double quotes, escaping, `$()` nesting, simple backticks, and arithmetic expansions containing substitutions. The guard's quote helper handles escaped nested backticks and interpolated heredocs before this splitter runs. The default stream is flat; `--scoped` adds typed enter/exit records so the checkout and push detectors can restore their directory after a substitution, and an operator record after each segment (`&&`, `||`, `;`, `;;`, `|`, `|&`, `&` or a newline) so they can tell whether a later segment runs only after it succeeded and whether it runs in a subshell. In scoped mode the substitution's records come first, in execution order, and the enclosing segment is emitted whole afterwards with a `SUBSTITUTION` placeholder in place of the substitution. The placeholder is unspaced inside double quotes, so `"$(…)"` stays one word, and glued to the whole word after `=`, `:` or a short-flag bundle ending in `o`, so `--push-option=$(…).skip`, `-o$(…)y` and `main:$(…)` stay one word instead of reading as the remote. Anywhere else it is spaced, so `push$(…)` keeps its `push` and `main$(…)` its `main`. A substitution that is exactly `git rev-parse --show-toplevel` (optionally with `2>/dev/null` or `2>&1`, a space after `2>` allowed) and starts its word becomes a `TOPLEVEL` placeholder instead, marked with a control character so a directory literally named `TOPLEVEL` is not read as one, and keeps the rest of its word (`TOPLEVEL/../other`): the guard resolves it to the top of the checkout the shell is in. A `|` inside `[[ … ]]` is a regex alternation, not a pipe, so it does not split the segment; a `[[` with no `]]` after it is a plain word, so it cannot merge the segments that follow. Process substitutions, `<(…)` and `>(…)`, are descended into like `$()`. It does not resolve commands built dynamically through variables or `eval`.

The scoped stream is a guard/helper protocol: update both together. A missing, malformed, or older helper stream intentionally hard-blocks a branch-switch or push check rather than skipping it.

The sharpest use is a **negative** test. `! grep` over a whole command line is satisfiable by any segment, so `gh api -X GET .../labels && gh api .../issues -f title=x` lets its own read disarm the gate for the mutation beside it. `destructive-guard`'s `seg_matches` uses this splitter to require the positives *and* the absence of the negative within one segment; read it for the pattern.

### `resolve-workdir.sh`

A guard that reads only `git -C` is inert for `cd <worktree> && git <verb>`, which is the shape a worktree-based workflow produces constantly: the session's cwd stays on the default branch, so the guard inspects the wrong repository and passes silently. `-C` wins when a command carries both, because that is what git itself acts on.

It also resolves a leading `~`, for the reason spelled out in the destructive-guard README: a quoted `~` never expands, `[ -d "~/repo" ]` is false, and the caller then falls back to its own cwd — a silent wrong answer rather than an error.

### `pr-author.sh`

Gates that behave differently on your own PR need an authorship answer inside a `PreToolUse` hook, where a network round-trip per command is not affordable. These helpers cache authorship indefinitely (it never changes) and repository visibility on a 7-day TTL (it does change, and a stale `PRIVATE` would grant on a repo since made public). A *failed* lookup is cached too, on a one-hour TTL, so an unresolvable repository does not pay a fresh API call on every command.

Every predicate fails closed: an unresolvable target, a missing `gh`, a timeout, and a public repository all answer false, so a caller gating on one keeps whatever verdict it already had. Every `gh` call goes through `gh_bounded`, which kills it and its process group after `PR_AUTHOR_TIMEOUT` seconds (default 8) using perl's `alarm`, because a `PreToolUse` hook that runs past its own timeout lets the tool run, and stock macOS ships no `timeout` binary. Without `perl` the call is not made, and the predicate answers false. The repository owner is never used as a proxy for visibility — an organisation carrying both public and private repositories would grant on exactly the class meant to be excluded.

### `hook-diag.sh`

The wrapper saves stderr in a temporary file and re-emits its bytes on exit 1 or 2 through the original descriptor, preserving the hook’s exit status. Exit-0 stderr is suppressed and recorded as `lost_stderr_on_exit_0`; model-facing advice belongs in stdout JSON.

Persisted records have exactly `ts`, `hook`, `exit`, `decision`, and `event`. `ts` is UTC; `exit` is an integer for exit records (including lost stderr) and null for events emitted before exit. No input, command, reason, stderr, path, session ID or caller detail is recorded.

| Field | Closed values |
|---|---|
| `hook` | `destructive-guard`, `worktree-preflight`, `skill-arg-substitution-guard`, `session-log`, `commit-attribution-guard`, `unknown` |
| `decision` | `none`, `allow`, `ask`, `deny`, `defer`, `notify`, `unknown` |
| `event` | `exit`, `lost_stderr_on_exit_0`, `invalid_json`, `splitter_missing`, `transcript_unreadable`, `derive_script_missing`, `derive_produced_nothing`, `derive_returned_no_path`, `prune_failed`, `unknown` |

Unrecognised categories become `unknown`. `hook_diag_event <event>` ignores extra arguments for compatibility; callers should pass only a fixed category. `HOOK_DIAG_DECISION` defaults to `none` and must be a closed value, such as `ask`, never a reason prefix.

| Variable | Effect |
|---|---|
| `HOOK_DIAG_LOG` | Nonzero exits and degradation events; default `/tmp/claude-hook-diag.log`. |
| `HOOK_DIAG_LOG_ALLOWS` | Any nonempty value enables exit-0 records in `HOOK_DIAG_ALLOW_LOG`. |
| `HOOK_DIAG_ALLOW_LOG` | Default `$HOME/.claude/local/hook-allow-decisions.log`. |
| `HOOK_DIAG_ASK_LOG` | Exit-0 `ask` records, independently of allow logging; default `$HOME/.claude/local/hook-ask-decisions.log`. |

Files are created with `umask 077` and rotate to `.prev` past 1 MB using portable `wc -c`. Log failures never change enforcement or exit status. Test harnesses must redirect all three destinations into isolated temporary directories. Archive old text-format logs before using JSON Lines readers; existing records are not converted.

## Usage in a hook

```bash
#!/usr/bin/env bash
# my-hook.sh

INPUT=$(cat)                              # MUST be first — hook-diag reads $INPUT
HOOK_DIAG_NAME="my-hook"
source "$(dirname "$0")/../_lib/hook-diag.sh"

# ... extract CMD, do work, source strip-cmd if needed:
source "$(dirname "$0")/../_lib/strip-cmd.sh"
CMD_STRIPPED=$(strip_cmd "$CMD")

if echo "$CMD_STRIPPED" | grep -qE '<bad-pattern>'; then
  echo "BLOCKED: <reason>" >&2
  exit 2
fi

exit 0
```

## Common authoring mistake

When using `${HOME}/.claude/hooks/_lib/strip-cmd.sh` style absolute paths in `source`, ALWAYS close the double quote:

```bash
# CORRECT
source "${HOME}/.claude/hooks/_lib/strip-cmd.sh"

# BROKEN — bash treats as multi-line string until next " on a later line.
# `bash -n` won't catch this; the next line gets eaten as part of the
# (malformed) source argument and the function silently fails to load.
source "${HOME}/.claude/hooks/_lib/strip-cmd.sh
CMD_STRIPPED=$(strip_cmd "$CMD")
```

The relative form `source "$(dirname "$0")/../_lib/strip-cmd.sh"` is more portable across install locations and is the recommended style.
