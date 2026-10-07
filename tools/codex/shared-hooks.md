# Sharing Hooks Between Claude Code and Codex

How to run the hook scripts you wrote for Claude Code under Codex as well, without a guard quietly turning into a pass.

## What carries over

Most of a Claude Code hook works under Codex as written:

- **The payload.** Every command hook receives one JSON object on stdin with `session_id`, `cwd`, `hook_event_name` and, for tool events, `tool_name` and `tool_input`. A shell command is `tool_name: "Bash"` with the command line in `tool_input.command`, in both tools. Codex adds `turn_id` and `model`, and a subagent's hooks see the parent's `session_id`.
- **The events.** `SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PermissionRequest`, `PostToolUse`, `PreCompact`, `PostCompact`, `SubagentStart`, `SubagentStop`, `Stop` and `SessionEnd` exist in both. Codex adds `Interrupt`. Claude Code has more, such as `Notification`, that Codex does not fire.
- **The shell.** Both run a hook `command` string through a shell (in Claude Code, the default shell form; its `args` exec form skips the shell), so `$HOME/.codex/hooks/<name>/<name>.sh` resolves in Codex as `$HOME/.claude/hooks/<name>/<name>.sh` does in Claude Code.
- **The timeout.** Both default a command hook to 600 seconds. Claude Code cuts `UserPromptSubmit` to 30 seconds, and Codex cuts `SessionEnd` and `Interrupt` to 1 second, with a 3-second maximum.
- **Concurrency.** Both start every matching hook for an event at once. Neither runs them in order, and one hook cannot stop another from starting.

## What changes meaning

The difference is in the **blocking contract**. Codex `PreToolUse` blocks in exactly two cases: exit 2 with a reason on stderr, or JSON with `permissionDecision: "deny"` (or the older `decision: "block"`). Every other outcome marks the hook run as failed, reports it, and **runs the tool**.

| A `PreToolUse` hook… | Claude Code | Codex |
|---|---|---|
| exits 2 with a reason on stderr | blocks | blocks |
| exits 2 with nothing on stderr | blocks | **runs the tool** — the run fails because the hook gave no reason |
| returns `permissionDecision: "ask"` | asks the user | **runs the tool** — `ask` is parsed but not supported |
| returns `continue`, `stopReason` or `suppressOutput` | honoured | **runs the tool** — unsupported on this event |
| exits with any other code, times out, or prints invalid JSON | non-blocking error; the tool runs | the tool runs |

The second and third rows are where a ported guard silently stops guarding. A soft-blocking guard asks before a force-push, a PR creation or a `kubectl delete`. Under Codex, every one of those asks becomes an unasked pass.

Two smaller shifts:

- **File edits arrive as a patch.** Codex edits files through `apply_patch`. Its `tool_name` is `apply_patch`, though a matcher can say `Edit` or `Write`. `tool_input.command` holds the whole patch, with `*** Add File:`, `*** Update File:`, `*** Delete File:` and `*** Move to:` headers, where Claude Code sends a `file_path` and the new content. A hook that reads `tool_input.file_path` sees nothing. Put an adapter in front of it that splits the patch into one Claude-shaped payload per file.
- **Every hook must be trusted before it runs.** Codex lists each non-managed hook definition and skips it until someone trusts it in `/hooks`. Trust is recorded against the definition's hash, so editing a definition sends it back for review. A guard added to `hooks.json` and never trusted does not run, and nothing warns at the moment it matters. Codex only prints a startup warning pointing at `/hooks`.

## The dispatcher

Register **one** hook per tool event in Codex, and have it run the Claude Code hooks as children: [`bash-hook-dispatcher.sh`](bash-hook-dispatcher.sh). It closes each gap above:

| Gap | What the dispatcher does |
|---|---|
| A child's `ask` passes under Codex | Blocks, quoting the child's reason. An ask becomes a block, the nearest outcome Codex can enforce; for a real prompt, see [Permissions](claude-code-translation.md#permissions). |
| A child's silent exit 2, crash or unsupported field passes | Blocks on `PreToolUse`, always writing a stderr reason. A crash under `PostToolUse` is reported, not escalated, because nothing is left to block. |
| Hooks run concurrently, in no fixed order | Runs children one at a time in list order. The first block wins, and later children never start. |
| One trust entry per hook | One definition to trust. Adding or removing a child is an edit to the dispatcher's list, not to `hooks.json`. |
| Several `additionalContext` strings | Merges them into one. |

Install it beside the children, in the same `<name>/<name>.sh` layout the [Claude Code hook examples](../claude/examples/hooks/) use, so each child's `../_lib/` helpers resolve:

```text
~/.codex/hooks/
├── bash-hook-dispatcher.sh
├── _lib/
├── destructive-guard/destructive-guard.sh
├── pr-create-guard/pr-create-guard.sh
└── post-push-hygiene/post-push-hygiene.sh
```

Register it for both Bash events in `~/.codex/hooks.json`:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": "$HOME/.codex/hooks/bash-hook-dispatcher.sh", "timeout": 180 }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": "$HOME/.codex/hooks/bash-hook-dispatcher.sh", "timeout": 180 }
        ]
      }
    ]
  }
}
```

Then open `/hooks` and trust both entries.

**Size the timeout for the whole chain.** The dispatcher's `timeout` covers every child in sequence, and a timed-out `PreToolUse` hook is one of the outcomes where Codex runs the tool. Set it above the summed worst case of the children, and give each network call inside a child its own short timeout. Then a slow API makes one child fail, rather than taking the whole dispatcher down unblocked.

**Trust covers the dispatcher, not its children.** Codex hashes the hook definition, which here is the dispatcher's command line. Adding a child, or changing one, is not shown in `/hooks`. That is the convenience in the table above and also a review gap: review the child list and the scripts in version control, because Codex will not. This follows from the documented trust model; it has not been tested against a changed child.

Verified behaviour of the script as published, with stub children and with this repo's `destructive-guard` copied in:

| Child outcome | Dispatcher |
|---|---|
| silent | exit 0, no output |
| two children add context | one merged `additionalContext` |
| `ask` | exit 2, reason names the child |
| `deny` from the first child | exit 2; the second child never runs |
| crash (exit 1) under `PreToolUse` | exit 2, "failing closed" |
| exit 2 with empty stderr | exit 2 with a generated reason |
| crash under `PostToolUse` | exit 1, reported |
| missing child script | exit 2 |
| real `destructive-guard`: `git status` / push to `main` / `gh pr create` | exit 0 / exit 2 (hard block) / exit 2 (its ask, blocked) |

## Hooks that cannot be shared

- **Approval hooks.** A Claude Code `PreToolUse` hook that asks has no Codex counterpart. The dispatcher turns its ask into a block. For a real prompt, use a `.rules` file with `decision = "prompt"` for the command prefix, which governs commands run outside the sandbox. A Codex `PermissionRequest` hook can allow or deny a request Codex was already going to raise. Neither one makes Codex ask about a command it would otherwise run.
- **Hooks that read the transcript.** Both tools pass `transcript_path`, and Codex says outright that its transcript format is not a stable interface for hooks. A hook that parses Claude Code transcripts needs its own Codex parser.
- **Claude-only events.** A `Notification` or `PostToolBatch` hook has no Codex event to attach to.

## Sources

- Codex [Hooks](https://developers.openai.com/codex/hooks): events, matchers, input fields, `PreToolUse` output, trust review, timeouts
- `openai/codex` source on `main`: `codex-rs/hooks/src/events/pre_tool_use.rs` (which outcomes block), `codex-rs/hooks/src/engine/command_runner.rs` (shell and timeout), `codex-rs/apply-patch/src/parser.rs` (patch headers)
- Claude Code [Hooks](https://code.claude.com/docs/en/hooks): parallel execution, exit codes, timeouts
