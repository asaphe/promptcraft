# statusline

Custom statusline command that displays contextual engineering state in the Claude Code status bar.

## What it shows

```text
[svc] ~/code/services | dev-123-feature* | PR#456 | prod-cluster | tf:prod | aws:prod | py:3.12 | wt:my-task | Claude Sonnet 4.6 | think | +120/-45 | ctx:42% | rl:62% 38m
```

All segments are conditional — only shown when the data is present:

| Segment | Condition |
|---------|-----------|
| `[label] ~/path` | Always; label from case match or `.workspace.repo.name` |
| `branch*` | On any branch; `*` when dirty |
| `PR#456` | `.pr.number` present in harness JSON; color by `.pr.review_state` (green approved or pending, red changes_requested, yellow draft) |
| `repo:PR#456` | Secondary repos with a cache file (see [PR badge](#pr-badge)) |
| `k8s-context` | `~/.kube/config` has a current context set |
| `tf:workspace` | `.terraform/environment` found walking up from cwd |
| `aws:profile` | `AWS_PROFILE` or `AWS_DEFAULT_PROFILE` is set |
| `py:3.12` | `.python-version` found walking up from cwd |
| `wt:name` | `--worktree` session name, or git worktree name from `.workspace.git_worktree` |
| `[session]` | Session name set via `/rename` |
| `+Ndirs` | Extra roots added via `--add-dir` / `/add-dir` |
| `model-name` | Always (dim) |
| `max`/`xhg`/`low`/`med` | Effort level from `.effort.level`, only when non-default (`high` hidden) |
| `think` | `.thinking.enabled` is true |
| `+120/-45` | Lines added/removed this session, when either is >0 |
| `ctx:42%` | Always; green <50%, yellow <80%, red ≥80% |
| `rl:62% 38m` | Only shown ≥50%; yellow, red ≥80%; suffix = minutes until `.rate_limits.five_hour.resets_at` |

Everything except the git/kubeconfig/file-walk segments comes from the harness JSON on stdin — one `jq` call extracts all fields as a TSV row, keeping per-tick subprocess count low. There is deliberately no cost segment: with usage-based limits the rate-limit segment is the actionable signal, and the cost number invites watching it instead.

## Configuration

```jsonc
{
  "statusLine": {
    "type": "command",
    "command": "/absolute/path/to/statusline-command.sh"
  }
}
```

## Repo label badge

The script tries to match the current working directory in a `case` statement first, then falls back to `.workspace.repo.name` from the harness JSON — no `git remote get-url` subprocess. The fallback means worktrees in `/tmp/` or unknown repos automatically get a label without any configuration:

```bash
# Case arms (customize for your layout):
case "$cwd" in
  */myorg/services*)       clone_label="svc";   clone_color='\033[36m' ;;
  */myorg/infrastructure*) clone_label="infra"; clone_color='\033[93m' ;;
esac
# Fallback for worktrees, new repos, etc.:
if [ -z "$clone_label" ] && [ -n "$repo_name" ]; then
  clone_label="$repo_name"
fi
```

## PR badge

The CWD repo's PR badge comes straight from the harness JSON (`.pr.number`, `.pr.review_state`) — no API call, no cache needed.

Secondary repos (other clones you work across in the same session) still use a cache file at `/tmp/claude-pr-cache-<repo>-<branch>` written by a `UserPromptSubmit` hook (e.g., `pr-context-inject`), because the native JSON only covers the cwd repo. Format: `<pr-number> <state> <url>` (single line). No cache file = no badge. List the repos to check in the `secondary_repos` array:

```bash
secondary_repos=("$HOME/code/infrastructure" "$HOME/code/workflows")
```

The cache is invalidated after `git push` (see `post-push-hygiene`); refresh it manually after `gh pr create/ready/close/reopen`.

## Known fix: bash 5.3 path shortening

bash 5.3 silently fails `${var/#$prefix/replacement}` when the expanded prefix starts with `/`. The script uses `sed "s|^${HOME}|~|"` instead, which works correctly on all bash versions.

## Known fix: kubeconfig quoted empty context

If your `~/.kube/config` has `current-context: ""` (valid YAML empty string), awk extracts the two literal `"` characters as a non-empty string. The script pipes through `tr -d '"'` to strip them, so an empty-string context produces no segment.
