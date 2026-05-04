# statusline

Custom statusline command that displays contextual engineering state in the Claude Code status bar.

## What it shows

```
[svc] ~/code/services | dev-123-feature* | PR#456 | prod-eks-01 | tf:prod | aws:prod | py:3.12 | wt:my-task | Claude Sonnet 4.6 | ctx:42% | rl:62% | $1.24
```

All segments are conditional — only shown when the data is present:

| Segment | Condition |
|---------|-----------|
| `[label] ~/path` | Always; label from case match or git remote name |
| `branch*` | On any branch; `*` when dirty |
| `PR#456` | Non-main branch + cache file exists (see [PR badge](#pr-badge)) |
| `k8s-context` | `~/.kube/config` has a current context set |
| `tf:workspace` | `.terraform/environment` found walking up from cwd |
| `aws:profile` | `AWS_PROFILE` or `AWS_DEFAULT_PROFILE` is set |
| `py:3.12` | `.python-version` found walking up from cwd |
| `wt:name` | Active worktree name from Claude Code JSON |
| `model-name` | Always (dim) |
| `ctx:42%` | Always; green <50%, yellow <80%, red ≥80% |
| `rl:62%` | Only shown ≥50%; yellow, red ≥80% |
| `$1.24` | Cost >$0; dim <$1, yellow $1–$5, red ≥$5 |

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

The script tries to match the current working directory in a `case` statement first, then falls back to the git remote name. The fallback means worktrees in `/tmp/` or unknown repos automatically get a label without any configuration:

```bash
# Case arms (customize for your layout):
case "$cwd" in
  */myorg/services*)       clone_label="svc";   clone_color='\033[36m' ;;
  */myorg/infrastructure*) clone_label="infra"; clone_color='\033[93m' ;;
esac
# Fallback for worktrees, new repos, etc.:
if [ -z "$clone_label" ]; then
  _remote=$(git -C "$cwd" remote get-url origin 2>/dev/null | sed 's|.*/||; s|\.git$||')
  [ -n "$_remote" ] && clone_label="$_remote"
fi
```

## PR badge

The PR badge reads from a file at `/tmp/claude-pr-cache-<repo>-<branch>` written by a `UserPromptSubmit` hook (e.g., `pr-context-inject`). This avoids an API call on every tick.

Format of the cache file: `<pr-number> <state> <url>` (single line).

If the cache file doesn't exist, no badge is shown. The cache is invalidated after `git push` (see `post-push-hygiene`) or after `gh pr create/ready/close/reopen` (see `pr-state-cache-invalidate`).

## Known fix: bash 5.3 path shortening

bash 5.3 silently fails `${var/#$prefix/replacement}` when the expanded prefix starts with `/`. The script uses `sed "s|^${HOME}|~|"` instead, which works correctly on all bash versions.

## Known fix: kubeconfig quoted empty context

If your `~/.kube/config` has `current-context: ""` (valid YAML empty string), awk extracts the two literal `"` characters as a non-empty string. The script pipes through `tr -d '"'` to strip them, so an empty-string context produces no segment.
