# tools/codex/

Running a Claude Code setup under OpenAI Codex as well: where each piece lives, and what changes meaning on the way.

This is a focused translation and Bash-hook dispatcher guide, not a full Codex configuration distribution. Dispatcher tests use stub children; they do not certify every translated example in a live client.

## What's here

- `claude-code-translation.md` — the map from Claude Code to Codex: instruction files, rules, skills, subagents, settings, permissions, MCP, plugins, the `config.toml` fields that need absolute paths, and delegating a task to `codex exec`.
- `shared-hooks.md` — running Claude Code hooks under Codex, the `PreToolUse` outcomes Codex lets through that Claude Code blocks or asks about, and the dispatcher that closes them.
- `bash-hook-dispatcher.sh` — the dispatcher itself: one registered Codex hook that runs Claude Code Bash hooks in order and fails closed.
- `test-bash-hook-dispatcher.py` — its fail-closed outcomes, run against stub children.

## When to read

- Adding Codex to a repo or machine that already has a `.claude/` setup.
- Porting a guard hook and needing it to keep blocking under Codex.
- Keeping a Codex `config.toml` in dotfiles.

## Not here

- Claude Code configuration itself → `tools/claude/`.
- Instruction-file layout shared by several tools (`AGENTS.md` as a pointer) → [`tools/cursor/multi-tool-coexistence.md`](../cursor/multi-tool-coexistence.md).
