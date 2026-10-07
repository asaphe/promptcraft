# Claude Code to Codex

Where each piece of a Claude Code setup lives in Codex, what carries over unchanged, and what changes meaning on the way.

Read this before porting a `.claude/` directory, or before running both tools against the same repository. Hooks get their own guide: [shared-hooks.md](shared-hooks.md).

## The map

| Claude Code | Codex | What changes |
|---|---|---|
| `~/.claude/CLAUDE.md` | `~/.codex/AGENTS.md`, or `AGENTS.override.md` beside it | Codex reads only the first non-empty one of the two. |
| `CLAUDE.md` in the repo | `AGENTS.md` from the project root down to the working directory | At most one file per directory, concatenated root-first. Reading stops at `project_doc_max_bytes`, 32 KiB by default. See [Instruction files](#instruction-files). |
| `.claude/rules/*.md` — always-loaded or path-scoped instructions | No equivalent. Fold them into `AGENTS.md`, using a nested `AGENTS.md` for a path scope | Codex **rules** are a different thing. They are `prefix_rule()` command policies in `.rules` files. See [Permissions](#permissions). |
| Skills: `.claude/skills/<name>/SKILL.md` | `.agents/skills/<name>/SKILL.md`, scanned from the working directory up to the repo root; `$HOME/.agents/skills` for personal ones | `SKILL.md` needs `name` and `description`. Claude-only frontmatter such as `allowed-tools` grants nothing in Codex. Invoke a skill with `$name` or pick it from `/skills`. |
| Subagents: `.claude/agents/<name>.md` | `.codex/agents/<name>.toml`; `~/.codex/agents/` for personal ones | Each file must set `name`, `description` and `developer_instructions`. It can also set `model`, `model_reasoning_effort`, `sandbox_mode` and `mcp_servers`. Model aliases do not carry over, and a Claude `tools:` list has no counterpart. |
| `hooks` in `settings.json` | `~/.codex/hooks.json` or `.codex/hooks.json`, or `[hooks]` in `config.toml` | Same JSON on stdin, but different blocking semantics, and every hook must be trusted before it runs. See [shared-hooks.md](shared-hooks.md). |
| `settings.json` | `~/.codex/config.toml`; `.codex/config.toml` for a project | Codex loads a project's `.codex/` layer only once the project is trusted. Several fields need absolute paths: see [config.toml paths](#configtoml-paths). |
| `permissions.allow` / `ask` / `deny` | `sandbox_mode`, `approval_policy` and `.rules` files | See [Permissions](#permissions). |
| MCP: `claude mcp add`, `.mcp.json` | `codex mcp add`, or `[mcp_servers.<name>]` in `config.toml` | A stdio server's `command` is executed without a shell. |
| Plugins: `.claude-plugin/plugin.json` | `plugin.json` at the plugin root, or `.codex-plugin/plugin.json` | OpenAI says it accepts "legacy and Claude-compatible manifests". Plugin hooks get `PLUGIN_ROOT` plus `CLAUDE_PLUGIN_ROOT` for compatibility. |

## Instruction files

The two tools can share one instruction file. Pick which tool owns the canonical copy:

- **`AGENTS.md` is canonical.** Claude Code (v2.1.277 or later) reads `AGENTS.md` on its own, but only when there is no `CLAUDE.md`, `.claude/CLAUDE.md` or `CLAUDE.local.md` in the working directory or above it. If the repo needs Claude-specific lines too, keep a `CLAUDE.md` whose first line is `@AGENTS.md` and add those lines below it.
- **`CLAUDE.md` is canonical.** Add `project_doc_fallback_filenames = ["CLAUDE.md"]` to the Codex `config.toml`. Codex then reads `CLAUDE.md` in any directory that has no `AGENTS.md` or `AGENTS.override.md`.

The second option has three gaps:

- Codex checks each directory for the file *name*, so `.claude/CLAUDE.md` and everything under `.claude/rules/` never load.
- `@path` imports are a Claude Code feature. Codex sees the `@` line as text.
- The combined text still stops at `project_doc_max_bytes`.

A rule-heavy Claude setup needs its always-loaded rules moved somewhere Codex reads.

## Permissions

Claude Code has one permission model: allow, ask and deny rules matched per tool call. Codex splits the same job across three mechanisms.

| Codex mechanism | Values | Role |
|---|---|---|
| `sandbox_mode` | `read-only`, `workspace-write`, `danger-full-access` | What a command can touch at all. `codex exec` defaults to `read-only`. |
| `approval_policy` | `on-request`, `never`, or a `granular` table | When Codex pauses for approval. |
| `.rules` files, e.g. `~/.codex/rules/default.rules` | `prefix_rule(pattern=[...], decision=...)` with `allow`, `prompt` or `forbidden` | Commands run **outside the sandbox**. When several rules match, the strictest decision wins. |

The closest Codex equivalent of a Claude `ask` rule on a command prefix is a `prefix_rule` with `decision = "prompt"`. A hook cannot fill that role: Codex `PreToolUse` hooks do not support `permissionDecision: "ask"`. See [shared-hooks.md](shared-hooks.md).

## config.toml paths

Some `config.toml` values go through a shell and some do not. Whether `~` and `$HOME` expand depends on which:

| Value | `~` | `$HOME` | Why |
|---|---|---|---|
| Hook `command` | yes | yes | Runs as `$SHELL -lc "<command>"`, falling back to `/bin/sh` |
| Fields typed as absolute paths: `model_instructions_file`, `log_dir`, `sqlite_home`, `model_catalog_json` | a leading `~` only | no | Parsed as an absolute path; only a leading `~` is expanded |
| `mcp_servers.<id>.command`, `args`, `cwd` | no | no | Started directly as a process, with no shell |
| `notify` | no | no | Executed from its argv, with no shell |
| `[projects."<path>"]` keys | no | no | Compared as exact strings against the working directory and repo root |
| `marketplaces.<name>.source`, local | — | — | The config reference says to use an absolute path. `codex plugin marketplace add ~/dir` expands `~/` before writing it. |

For an MCP server, either write the absolute path, or let a shell do the expansion:

```toml
[mcp_servers.my-server]
command = "/bin/sh"
args = ["-c", "exec \"$HOME/.local/bin/my-mcp-server\""]
```

`HOME` is on the short list of variables Codex passes to a stdio MCP server, so the `sh -c` form resolves it. This follows from the source; it has not been exercised against a live server here.

**Codex also writes absolute paths into `config.toml` itself.** Trusting a project adds a `[projects."/abs/path"]` table. Trusting a hook adds a `[hooks.state."<abs path to hooks.json>:<event>:<group>:<index>"]` table carrying its `trusted_hash`. The project key format is documented. The hook-state key shape is observed, not documented. Either way, a `config.toml` kept in a dotfiles repo cannot be home-directory-independent. Re-root it on a machine with a different home (`sed -i.bak "s#$OLD_HOME#$HOME#g" ~/.codex/config.toml`, with `OLD_HOME` set to the previous home directory), as the [portability guide](../claude/guides/portability-guide.md#what-git-cannot-carry) describes for the other items git cannot carry.

## Delegating to Codex from Claude Code

To hand a bounded task to Codex from a Claude Code session, run `codex exec` non-interactively:

```bash
codex exec --sandbox workspace-write "<scoped objective>" </dev/null
```

- **`</dev/null`**: `codex exec` reads piped stdin as extra context, even when a prompt argument is given. An agent's shell tool can leave stdin as a pipe that never closes, and the run then waits forever. The wait is observed, not documented.
- **`--sandbox`**: `codex exec` runs in a `read-only` sandbox by default, so a task that edits files needs `workspace-write`. `--full-auto` is deprecated.
- **`-o <file>`** (`--output-last-message`) writes the final message to a file. `--json` streams every event as JSON Lines.
- **Prompt from a file**: pass a long objective, or one containing backticks or quotes, as a file the task reads. Inside a shell-quoted argument, a backtick or `$(...)` is expanded before Codex ever sees it.

Judge what comes back as you would any contributor's diff. The run's exit status shows it finished, not that the change is right.

## Sources

Checked against current documentation and the `openai/codex` source on `main`:

- [Hooks](https://developers.openai.com/codex/hooks), [Configuration reference](https://developers.openai.com/codex/config-reference), [AGENTS.md](https://learn.chatgpt.com/docs/agent-configuration/agents-md), [Rules](https://learn.chatgpt.com/docs/agent-configuration/rules), [Subagents](https://learn.chatgpt.com/docs/agent-configuration/subagents), [Build skills](https://learn.chatgpt.com/docs/build-skills), [Build plugins](https://developers.openai.com/plugins/build/plugins), [Non-interactive mode](https://learn.chatgpt.com/docs/non-interactive-mode)
- Source in `openai/codex`: `codex-rs/hooks/src/engine/command_runner.rs` (hook shell), `codex-rs/utils/absolute-path/src/lib.rs` (`~` expansion), `codex-rs/rmcp-client/src/stdio_server_launcher.rs`, `program_resolver.rs` and `utils.rs` (MCP launch and environment), `codex-rs/hooks/src/registry.rs` (`notify`), `codex-rs/config/src/project_trust.rs` (project keys)
- Claude Code: [Memory and AGENTS.md](https://code.claude.com/docs/en/memory), [Hooks](https://code.claude.com/docs/en/hooks)
