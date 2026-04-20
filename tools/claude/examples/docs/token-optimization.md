# Token & Context Window Optimization

Reference files consume tokens. Be smart about when and how you load them.

## Rules

- **Read on-demand, not upfront** — Only read reference files (`CLAUDE.md`, `specs/`, `docs/`) when the current task requires them. Don't preload everything "just in case."
- **Summarize large outputs immediately** — After running commands that produce large output (terraform plan, kubectl logs, git diff), summarize the key findings in your response. Don't rely on the raw output surviving context compression.
- **Avoid re-reading unchanged files** — If you read a file earlier in the session and it hasn't been modified, reference your earlier read instead of reading again.
- **Prefer targeted reads** — Use `offset`/`limit` on large files, `--tail` on log commands, `-compact-warnings` on terraform plan. Don't dump entire files when you need 10 lines.
- **Watch for context pressure** — When a session has been running long (many tool calls, large outputs), summarize the current state (branch, what's done, what remains) before context compresses. The `PreCompact` hook automatically preserves correction signals, but operational state summaries require explicit capture.
- **CLAUDE.md hierarchy** — Files closer to the working directory override general rules. Don't read the root CLAUDE.md when working in `devops/terraform/` if `devops/CLAUDE.md` already covers the topic.
