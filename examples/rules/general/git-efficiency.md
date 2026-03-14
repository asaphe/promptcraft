# Git & GitHub CLI Efficiency

- **Check git state once at task start, not before every operation** — Run `git status` and `git branch --show-current` once when beginning a task. Do not re-run before every add/commit/push unless a command may have changed the state (e.g., after a rebase, merge, or checkout). Exception: in worktrees or parallel sessions, always verify branch before commit per `git-safety.md`.

- **Chain `git add` and `git commit` in a single Bash call** — Always use `git add <files> && git commit -m "..."` as one command, not two separate Bash tool calls. The commit depends on staging — there's no reason to separate them. If the commit fails due to a pre-commit hook, files remain staged — retry with just `git commit`, do not re-add.

- **Use `gh pr view --json` with specific fields** — Never use bare `gh pr view` or raw `gh api repos/.../pulls/N` when `gh pr view N --json field1,field2` gets exactly what you need. Specify only the fields required (e.g., `--json state,reviewDecision,statusCheckRollup`).

- **Use `--jq` on `gh` commands to filter at the source** — Apply `--jq` filters directly on `gh` commands instead of piping through `jq`. Example: `gh pr view 123 --json reviews --jq '.reviews[] | select(.state == "CHANGES_REQUESTED")'`.

- **Run `git fetch` once per session** — A single `git fetch origin` at session start is sufficient. Do not re-fetch before every push, pull, or branch operation unless a command indicates stale refs (e.g., "remote ref not found").

- **Use `git diff --stat` before full diffs** — Start with `git diff --stat` to see which files changed and by how much. Only read full diffs for files that matter.

- **Prefer `gh` CLI over `gh api` for standard operations** — Use `gh pr list`, `gh pr view`, `gh pr create`, `gh run view` etc. instead of raw `gh api` REST calls. The CLI handles pagination, auth, and output formatting. Reserve `gh api` for operations the CLI doesn't support natively (e.g., GraphQL mutations, dismissals).
