# Hook Tests

Three harnesses for testing Claude Code hooks, each covering an axis the others cannot.

| Tool | Covers | Answers |
|---|---|---|
| `run-fixtures.py` | one hook, deeply, from a TSV | does this hook reach the right verdict on each command? |
| `probe-hooks.py` | every hook, shallowly | does its payload reach anyone at all? |
| `mutate-fixtures.py` | the fixtures themselves | would this suite notice if the hook broke? |

## Why three

A hook test is unusually easy to write so that it cannot fail, and there are three distinct ways to get there.

**Comparing exit codes scores a working hook and a silent one identically.** A guard that emits `permissionDecision: "ask"` exits 0, and so does a guard that decided to do nothing. A reminder that emits `additionalContext` exits 0 too. So `run-fixtures.py` asserts an *outcome* — `allow` / `ctx` / `ask` / `deny` / `soft` / `hard` / `block` — rather than a number.

**A hook can be individually correct and collectively unarmed.** Claude Code discards stderr when a hook exits 0, treats exit 1 as a non-blocking error rather than a block, and adds bare stdout to context only on `UserPromptSubmit`, `UserPromptExpansion` and `SessionStart`. A hook writing its advice to the wrong stream does everything else right and delivers nothing — and every exit-code assertion in the world scores it as passing. `probe-hooks.py` asserts the channel.

**A fixture that has never failed is indistinguishable from one that cannot.** Guard fixtures get written by reading the hook, so they systematically encode whatever the hook already does. `mutate-fixtures.py` breaks the hook on purpose and requires the suite to notice.

## Running them

```bash
# One hook, from fixtures/<hook>.tsv
python3 run-fixtures.py destructive-guard --hooks-dir ../hooks

# Delivery contracts across every hook, plus the selftest that proves they fire
python3 probe-hooks.py --hooks-dir ../hooks
python3 probe-hooks.py --selftest

# Break each hook on purpose; every mutation must be caught
python3 mutate-fixtures.py --hooks-dir ../hooks

# Compare selected expansion fixtures with Bash using inert command stubs
python3 test-expansion-semantics.py
```

`--hooks-dir` resolves both layouts: flat `<dir>/<name>.sh`, which is how hooks sit in an installed `~/.claude/hooks/`, and nested `<dir>/<name>/<name>.sh`, which is how they sit in this repo. Installed alongside your own hooks as `~/.claude/hooks/tests/`, the default is already right and the flag can be dropped.

`test-expansion-semantics.py` checks selected destructive-guard fixtures against `/bin/bash` and, when present, Homebrew Bash. It first asserts the ordered calls to inert command stubs, then checks the guard verdict. Payloads execute from reviewed fixture files with a temporary-only `PATH`, controlled startup files, and temporary working directories. This is a test harness, not a sandbox for untrusted shell input.

An `#!oracle` line selects the following TSV case. Its tab-separated fields are the case name, expected stub trace (`-` for no calls), optional setup name, and optional setup-specific verdict. The ordinary fixture runner ignores these lines; a cross-repository checkout case needs the oracle's two-repository setup to exercise the hard block. Missing or invalid quote helpers are tested separately against temporary hook copies. Decoded payloads pass tripwires for absolute paths, destructive filesystem commands, and environment overrides before execution.

## Fixture format

`fixtures/<hook>.tsv`, one case per line as `expected <TAB> command`, `#` for comments.

| Outcome | Means |
|---|---|
| `allow` | exit 0, nothing the harness recognises on stdout |
| `ctx` | exit 0 carrying `hookSpecificOutput.additionalContext` — a reminder fired |
| `ask` / `deny` | exit 0 carrying that `permissionDecision` |
| `soft` | exit 1 — **not a block**; Claude Code prints a notice and runs the tool |
| `hard` | exit 2 — the only blocking code |
| `block` | exit 0 carrying top-level `{"decision": "block"}` — a Stop hook refusing the yield |
| `raw` / `=<cmd>` | for a rewrite hook: ran without rewriting, or rewrote to exactly this |

`0`, `1` and `2` are accepted as aliases for `allow`, `soft` and `hard`.

File directives, each on its own line:

| Directive | Effect |
|---|---|
| `#!event <name>` | `PreToolUse` (default), `PostToolUse`, `UserPromptSubmit`, `Stop` |
| `#!tool <name>` | `Bash` (default), `Write`, `Edit`, `MultiEdit` |
| `#!escapes` | column 2 honours `\n`, `\t` and `\xHH` |
| `#!setup <name>` | build live state from `fixture_env.py` before the cases run |

### Three details that decide whether a fixture tests anything

**`#!tool` picks the payload key, and the wrong key passes vacuously.** Write carries new content under `content`, Edit under `new_string`, MultiEdit under `edits[].new_string`. A hook reading a key the harness did not populate sees an empty string, matches nothing, and every case in the file goes green.

**`#!escapes` is opt-in per file, not universal.** A literal backslash-n is valid shell text — a `perl` string, a commit message — and unescaping it would rewrite the input a case was written to assert. `\xHH` exists for a narrower reason: a fixture for a secret detector has to contain the thing the detector detects, and a sibling write guard will block the file for carrying it. Spelling the first byte as hex keeps the file clean to every scanner while the harness reconstructs the literal in memory. A fixture that dodged this by weakening its trigger would pass while testing nothing.

**`<absent>` in column 2 omits `tool_input` entirely.** That is the third control every guard fixture owes — block-case, allow-case, and input-unavailable — because a guard reads its subject through one extraction, and an empty result is indistinguishable from "nothing to guard". The branch becomes reachable in production the moment that extraction breaks. The fixture does not assert a universal verdict there; it pins whichever way the hook currently resolves it, so a later edit cannot flip a considered fail-open into an unconsidered one in silence.

## `fixture_env.py` — hooks that read state, not the command

Some guards do not decide from the command string at all. They ask git what is staged, whether the branch was pushed, whether `origin/main` resolves. Point those at whatever happens to be in `--cwd` and the suite flaps with the day; point them at nothing and they return at their first bail, passing every case without ever reaching a branch. Either way the fixture asserts nothing while looking green.

A `#!setup` name builds that state in a temp directory and exposes paths as `{token}` substitutions:

```text
#!setup pr-create
hard  <TAB>  cd {dirty} && gh pr create --title x --body y
ctx   <TAB>  cd {ready} && gh pr create --title x --body y
allow <TAB>  cd {noorigin} && gh pr create --title x --body y
```

`<TAB>` above stands for one literal tab — the separator is a real tab character, and
the surrounding spaces here are only for alignment in this README.

Substitution is by exact token name rather than `str.format`, because commands legitimately contain braces — a `jq` filter is not a placeholder.

Note what the third line pins. With no `origin/main`, the zero-diff check *could not run*, and a guard that blocks there asserts a measurement nobody took. The case exists to make that fail-open a recorded decision rather than an accident.

## Writing mutations

`mutations.json` maps a hook to a list of `{why, delete_matching | replace}`. Each one should break **one** behaviour the fixture claims to cover — one that kills a block branch, one that kills a false-positive defence. A single "neuter the whole hook" mutation only proves the suite notices a corpse.

Two things are checked per mutation, and the second is the one that matters:

1. The broken hook fails its suite.
2. The mutation actually changed the file.

Without (2) a mutation whose pattern has drifted out of the hook silently applies to nothing, the pristine hook passes its own suite, and the run reports the *fixture* as vacuous when the truth is that the mutation was. That reads as a real finding and sends you off to rewrite a fixture that was fine.

A useful signal in the output: distinct mutations should produce *distinct* pass counts. If every mutation drops the suite to the same number, they are all hitting the same branch.

## Two things that bite when authoring these

**A probe payload must not contain the hook's own trigger on your command line.** Writing a fixture for a guard by pasting the guard's trigger into a shell command fires the guard on the authoring command. Write payloads to a file with a non-shell tool, then read that file — which is also why the triggers in `fixture_env.py` and `probe-hooks.py` are assembled from parts rather than written whole.

**Redirect the diagnostic logs.** Both harnesses point `HOOK_DIAG_LOG` and friends at a temp directory, because a fixture run is not a real firing: left alone, hundreds of synthetic decisions land in the live corpus and inflate exactly the counts that corpus is consulted for.

## Relationship to `.claude/evals/`

This repo also runs a smaller eval harness at `.claude/evals/` against its own dogfooded hooks, wired into CI. That one asserts the union of stdout and stderr, which cannot distinguish a delivered payload from a discarded one — the gap `probe-hooks.py` exists to close. Treat this directory as the fuller pattern to adopt; the two are not redundant, they assert different things.
