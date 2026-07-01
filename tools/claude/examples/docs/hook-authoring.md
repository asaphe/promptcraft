# Hook Authoring

- **POSIX ERE only in hook scripts** — macOS `grep -E` does not support `\s`, `\d`, `\b`, or other PCRE shortcuts. Use literal spaces, `[0-9]`, `[[:space:]]`. Use `grep -qE -- 'pattern'` when patterns start with `-`.
- **Test hooks before registering** — `echo '{"tool_input":{"command":"..."}}' | ~/.claude/hooks/hook-name.sh` to verify output and exit code.
- **Keep utility scripts in a dedicated dir** (e.g. `~/.claude/scripts/`) — referenced by hooks or invoked directly. Sharing one helper across hooks beats duplicating logic per hook.
- **Session analytics** — Mine `~/.claude/projects/*/*.jsonl` (excluding `*/subagents/*`) to find tool-call waste. Run periodically. See `session-analytics-guide.md` for queries.
