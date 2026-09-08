# `_lib/` — shared utilities for hook authors

This directory holds shell utilities that other hooks source. The leading underscore signals "infrastructure, not a hook itself" — the loader doesn't try to register `_lib/*.sh` as hooks.

## What's here

| File | Purpose |
|------|---------|
| [`strip-cmd.sh`](strip-cmd.sh) | `strip_cmd "$CMD"` blanks heredoc bodies and `-m`/`--message` contents; `strip_quoted_args "$CMD"` blanks quoted literals. Both keep pattern matching on the command surface rather than on text a command carries. |
| [`hook-diag.sh`](hook-diag.sh) | Diagnostic wrapper. Sourced AFTER reading stdin into `$INPUT`. Logs hook name, exit code, command and stderr tail to a rotating log, re-emits captured stderr on exit 1 and exit 2 so the reason reaches the model, and records a hook that wrote to stderr on exit 0 — where the harness discards it. |
| [`strip-quoted-args.pl`](strip-quoted-args.pl) | Character-walk backend for `strip_quoted_args`. Reads a command on stdin, writes it back with quoted data blanked and quoted *code* preserved. |
| [`split-cmd-segments.pl`](split-cmd-segments.pl) | Splits a command line into NUL-delimited segments on unquoted separators, so a flag test runs against the segment that owns the flag. |
| [`resolve-workdir.sh`](resolve-workdir.sh) | `resolve_workdir "$CMD"` returns the repository a git command acts on — via `git -C <dir>` or a leading `cd <dir> &&` — or nothing. |
| [`pr-author.sh`](pr-author.sh) | Cached predicates for PR authorship and repository visibility, for gates that treat a self- or bot-authored PR differently from someone else's. |

## Why these exist

### `strip-cmd.sh`

`grep -qE 'gh +pr +close'` will hit on a commit message that contains the words "gh pr close" — typically when the model writes a heredoc explaining what NOT to do. `strip_cmd` removes the heredoc body before matching, so guard patterns only fire on the actual command surface.

The heredoc pattern deliberately allows text between the delimiter word and the newline. `cat <<EOF > notes.txt` puts a redirect there, and a pattern requiring only whitespace leaves that whole body unstripped — the case where a body is most likely to contain command-looking prose.

**But that class must exclude command boundaries**, and getting this wrong is a total bypass rather than a missed strip. With a permissive `[^\n]*`, the marker line's match runs past a `;` or `&&` and swallows *the next command with it* — so `cat <<EOF; git push origin main` deletes the push from the text every guard pattern then examines, and bash runs it anyway as a separate command. The class is therefore `[^\n;&|(` + backtick + `]*`: a redirect still strips, while `;`, `&`, `|`, `(` and a backtick each stop the match and leave the following command visible. Over-stripping here disables every rule at once, so the failure is silent and total; under-stripping merely over-fires.

`strip_cmd` also returns its input **unchanged** when `perl` is unavailable, rather than empty. An empty result would make every downstream `grep` match nothing, which reads as "no dangerous pattern found" — a guard that silently stops guarding.

### `strip-quoted-args.pl`

`strip_cmd` handles heredocs and message flags. Quoted arguments are the same problem one level down: `git grep -rn 'git checkout main' .` is a search, and a detector looking for a *command invocation* must not fire on it.

Two kinds of quoted span survive blanking, because in both the text really is code: a command substitution at any depth, and a payload handed to a shell (`bash -c "…"`, `eval "…"`, `ssh host "…"`). It is a character walk rather than a regex because quote pairing by regex mis-associates quotes on a busy command line, and cannot tell that `"$(terraform apply)"` inside double quotes is code rather than text.

Use it only for detectors matching an invocation. A detector matching *content* — a URL, a SQL statement — must run on the unstripped command, since that content is legitimately quoted.

### `split-cmd-segments.pl`

A flag test written against the whole command line answers for the wrong command. `gh pr list --json url | jq -r 'select(.state)'` carries a `select` belonging to `jq`; an allowlist keyed on `gh` flags cannot tell. Splitting first lets each detector run against the segment that owns what it is testing.

Segments are NUL-delimited because a segment may itself contain newlines — a quoted multi-line body — so a newline-delimited stream cannot be read back into whole segments.

The sharpest use is a **negative** test. `! grep` over a whole command line is satisfiable by any segment, so `gh api -X GET .../labels && gh api .../issues -f title=x` lets its own read disarm the gate for the mutation beside it. `destructive-guard`'s `seg_matches` uses this splitter to require the positives *and* the absence of the negative within one segment; read it for the pattern.

### `resolve-workdir.sh`

A guard that reads only `git -C` is inert for `cd <worktree> && git <verb>`, which is the shape a worktree-based workflow produces constantly: the session's cwd stays on the default branch, so the guard inspects the wrong repository and passes silently. `-C` wins when a command carries both, because that is what git itself acts on.

It also resolves a leading `~`, for the reason spelled out in the destructive-guard README: a quoted `~` never expands, `[ -d "~/repo" ]` is false, and the caller then falls back to its own cwd — a silent wrong answer rather than an error.

### `pr-author.sh`

Gates that behave differently on your own PR need an authorship answer inside a `PreToolUse` hook, where a network round-trip per command is not affordable. These helpers cache authorship indefinitely (it never changes) and repository visibility on a 7-day TTL (it does change, and a stale `PRIVATE` would grant on a repo since made public). A *failed* lookup is cached too, on a one-hour TTL, so an unresolvable repository does not pay a fresh API call on every command.

Every predicate fails closed: an unresolvable target, a missing `gh`, a timeout, and a public repository all answer false, so a caller gating on one keeps whatever verdict it already had. The repository owner is never used as a proxy for visibility — an organisation carrying both public and private repositories would grant on exactly the class meant to be excluded.

### `hook-diag.sh`

A common Claude Code hook authoring pitfall: a hook exits 1 or 2 with a `>&2` message, but Claude Code's UI shows "No stderr output" and the model doesn't know why it was blocked. The cause is that Claude Code captures stderr through a pipe, and depending on shell-buffering / FD layout the message can be lost.

`hook-diag.sh` solves this by saving the original stderr to FD 3, redirecting FD 2 to a temp file, and on exit re-emitting the captured content via `exec 2>&3; echo "$captured" >&2`. The model sees the reason; the user sees a clean log at `/tmp/claude-hook-diag.log` for non-zero exits.

Exit 2 is the only code that blocks the tool call. On exit 1 the tool still runs, and **on exit 0 the harness discards stderr entirely** — so a hook that computes an advisory, writes it to stderr and exits 0 is talking to nobody, looks correct in review, and never fires. Because this wrapper captures FD 2, it is also what hides that. It now logs the combination as `event=LOST_STDERR_ON_EXIT_0`. A reminder that must reach the model on a pass path belongs on **stdout**, as `hookSpecificOutput.additionalContext`.

Optional logging, off unless you opt in:

| Variable | Effect |
|----------|--------|
| `HOOK_DIAG_LOG` | Override the block log path — a replay or test harness must not append to the corpus it reads. |
| `HOOK_DIAG_LOG_ALLOWS` | Set to any non-empty value to log exit-0 decisions to `HOOK_DIAG_ALLOW_LOG`. Off by default: allows outnumber blocks by orders of magnitude. |
| `HOOK_DIAG_DECISION` | Set by the hook before returning, e.g. `ask:<trigger>`. An ask and a plain allow are both exit 0, so without this, prompt volume is unmeasurable. Any value starting `ask` is also appended to `HOOK_DIAG_ASK_LOG`. |

`hook_diag_event <NAME> [detail]` records something a hook notices about **itself** — a degraded dependency, a missing helper. Exit 0 discards stderr, so without it a hook that quietly falls back to a weaker mode leaves no trace at all; `destructive-guard` uses it to record `SPLITTER_MISSING`.

Newlines are flattened out of every logged field. The log is a line-oriented record format, so an unflattened field lets a command body forge a `---`, `ts=` or `hook=` line and desynchronise anything parsing it.

**These records contain verbatim command text, which can include credential material** — `kubectl patch secret … -p '{"data":{...}}'` is on the ask-trigger list, so it lands in the ask log in full. Log files are therefore created with `umask 077`, and the two decision logs default to `$HOME/.claude/local/` rather than a predictable name in a world-writable directory. `HOOK_DIAG_LOG` keeps its historical `/tmp` default for compatibility; on a shared host, point it somewhere private.

Rotation uses `wc -c`, not `stat -f%z` — the latter is BSD-only, and on Linux it silently never rotated, which mattered most for the one file holding raw command text.

## Usage in a hook

```bash
#!/usr/bin/env bash
# my-hook.sh

INPUT=$(cat)                              # MUST be first — hook-diag reads $INPUT
HOOK_DIAG_NAME="my-hook"                  # optional, otherwise uses basename
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
