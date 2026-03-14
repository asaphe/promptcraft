# CI Monitoring & AWS Session Rules

- **Proactively monitor CI after pushing** — After pushing commits, monitor CI in the background (use `run_in_background` or a subagent). Use the GitHub API for status — not `gh pr checks` which misreports cancellations as failures (see `ci-runners.md`). On real failure, fetch logs with `gh run view <run-id> --log-failed`, diagnose, and fix. The user should never have to paste CI error logs.

- **Never poll CI in the foreground** — CI monitoring (`gh run view`, `gh run watch`, `gh pr checks`) must always use `run_in_background: true` or be delegated to a subagent. A single `gh run view` to check status once is fine, but any loop or repeated check must be background.

- **Check AWS session validity before re-authenticating** — Before running `aws sso login`, check with `aws sts get-caller-identity --profile <profile>` — only re-authenticate on failure. Within a session, verify auth once at the start; do not re-check between individual commands unless one returns an auth error.

- **Use official live docs, not the HubFS PDF, for claude-code-action guidance** — The "Complete Guide to Building Skills for Claude" PDF (resources.anthropic.com/hubfs/...) is a marketing document and goes stale. The authoritative always-current references are: `https://code.claude.com/docs/` (Claude Code, GitHub Actions, Skills, Memory) and `https://platform.claude.com/docs/` (API, tool use, SDK). When verifying action parameters, prompt patterns, or `--allowedTools` syntax, fetch from the live docs, not the PDF.

- **Use `--append-system-prompt` for shared instructions across claude-code-action invocations** — When the same instruction applies to every review job (e.g., a FINAL STEP), put it in the composite action's `claude_args` via `--append-system-prompt "..."` rather than repeating it in every workflow prompt. Repeated identical prompt text across jobs is a maintenance hazard — a single change requires updating N places.
