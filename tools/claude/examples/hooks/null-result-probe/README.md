# Null Result Probe

A **PostToolUse** hook on `Bash` that nudges for a control probe when a command returned nothing, or a scanner reported a confident zero, and the command contains a construct that is known to collapse silently.

## Why This Exists

A command that matched nothing and a command whose glob, file list or pathspec silently collapsed produce byte-identical output. Reading that emptiness as "nothing there" is the first row of the [evidence-nulls rule](../../rules/general/evidence-nulls.md): the query never ran. The shell constructs that cause it are catalogued in [`shell-traps.md`](../../rules/general/shell-traps.md).

This hook backs that rule at the moment the result is read, with a nudge to run a control that must produce output.

## Behavior

The hook reads only the response content and never tests an exit code (the PostToolUse payload carries none; `PostToolUse` fires only after a tool call succeeds).

| Output | Command contains | Action |
|--------|------------------|--------|
| Empty (or whitespace under 400 bytes) | A suspicious construct | Nudge: run a control that must produce output |
| A short zero-findings line (`0 matches`, `no issues found`, ...) | A suspicious construct | Nudge: confirm how many files the scan opened |
| Anything else, backgrounded or no-output-expected commands, redirected stdout | any | Silent |

Suspicious constructs: a self-declared control probe, a git pathspec after `--`, `find` on an unresolved `/tmp` without `-L`, an unquoted `$` expansion, and an unquoted path glob. Quoted data is blanked first through `_lib/strip-cmd.sh` when it is present, so a construct inside a quoted string does not count.

- **Exit 0 always** — never blocks
- On a nudge, emits `hookSpecificOutput.additionalContext` JSON on stdout
- Observed, not documented: the Bash `tool_response` also carries `noOutputExpected` and `backgroundTaskId`, which the hook uses to stay silent, and the Bash tool reports an exit 1 from `grep`, `rg`, `find`, `diff` or `test` as a successful result. The documented fields are `stdout`, `stderr`, `interrupted` and `isImage`; if the undocumented ones disappear, the hook nudges more often rather than less
- Every Bash call appends one line to a log (timestamp, `fire=0|1`, reason; command text only on a fire), so the fire rate against all calls can be measured. If it is high, the nudge is noise and the hook should go

## Configuration

| Variable | Default | Meaning |
|----------|---------|---------|
| `NULL_RESULT_PROBE_LOG` | `$HOME/.claude/local/null-result-probe.log` | The fire-rate log; rotates to `.prev` past 1 MB |
| `CLAUDE_HOOK_FIXTURE_RUN` | unset | When non-empty, nothing is logged (for test runs) |

## Installation

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "\"$HOME/.claude/hooks/null-result-probe/null-result-probe.sh\""
          }
        ]
      }
    ]
  }
}
```

Copy `_lib/strip-cmd.sh` and `_lib/strip-quoted-args.pl` alongside it (see [`_lib/`](../_lib/)). Requires `jq`; `perl` is used when the helpers are present.
