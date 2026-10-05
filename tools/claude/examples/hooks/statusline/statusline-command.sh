#!/usr/bin/env bash
# Claude Code statusline — segments and conditions documented in README.md alongside this script.

input=$(cat)

# \x1f join: tab is IFS-whitespace, so empty TSV fields collapse and shift later values left
IFS=$'\x1f' read -r model used rate5h worktree_name effort_level thinking_enabled \
  repo_name git_worktree pr_number pr_review_state \
  lines_added lines_removed session_name added_dirs_count rl_resets_at < <(
  echo "$input" | jq -r '[
    (.model.display_name // ""),
    (.context_window.used_percentage // ""),
    (.rate_limits.five_hour.used_percentage // ""),
    (.worktree.name // ""),
    (.effort.level // ""),
    (if .thinking.enabled == true then "true" else "" end),
    (.workspace.repo.name // ""),
    (.workspace.git_worktree // ""),
    (if .pr.number != null then (.pr.number | tostring) else "" end),
    (.pr.review_state // ""),
    (if ((.cost.total_lines_added // 0) > 0) then (.cost.total_lines_added | tostring) else "" end),
    (if ((.cost.total_lines_removed // 0) > 0) then (.cost.total_lines_removed | tostring) else "" end),
    (.session_name // ""),
    ((.workspace.added_dirs // []) | length | if . > 0 then tostring else "" end),
    (if .rate_limits.five_hour.resets_at != null then (.rate_limits.five_hour.resets_at | tostring) else "" end)
  ] | join("\u001f")'
)

cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // ""')
aws_profile="${AWS_PROFILE:-${AWS_DEFAULT_PROFILE:-}}"
# bash 5.3 silently fails ${var/#$prefix/~} when prefix starts with /; use sed
short_cwd=$(printf '%s' "$cwd" | sed "s|^${HOME}|~|")

# Git branch + dirty flag
git_branch=""
git_dirty=""
if git_branch_raw=$(git -C "$cwd" --no-optional-locks branch --show-current 2>/dev/null); then
  git_branch="$git_branch_raw"
  if ! git -C "$cwd" --no-optional-locks diff --quiet 2>/dev/null || \
     ! git -C "$cwd" --no-optional-locks diff --cached --quiet 2>/dev/null; then
    git_dirty="*"
  fi
fi

# K8s current context — parse kubeconfig directly (no subprocess fork)
k8s_context=""
kubeconfig="${KUBECONFIG:-$HOME/.kube/config}"
if [ -f "$kubeconfig" ]; then
  # tr -d '"' strips YAML-quoted empty values (current-context: "")
  k8s_context=$(grep 'current-context:' "$kubeconfig" 2>/dev/null | awk '{print $2}' | tr -d '"' | head -1)
fi

# Terraform workspace — walk up from cwd looking for .terraform/environment
tf_workspace=""
dir="$cwd"
while [ "$dir" != "/" ] && [ -n "$dir" ]; do
  if [ -f "$dir/.terraform/environment" ]; then
    tf_workspace=$(cat "$dir/.terraform/environment" 2>/dev/null | tr -d '[:space:]')
    break
  fi
  dir=$(dirname "$dir")
done

# pyenv version — walk up from cwd, abbreviate to major.minor
py_version=""
dir="$cwd"
while [ "$dir" != "/" ] && [ -n "$dir" ]; do
  if [ -f "$dir/.python-version" ]; then
    raw=$(head -1 "$dir/.python-version" 2>/dev/null | tr -d '[:space:]')
    py_version=$(echo "$raw" | grep -oE '^[0-9]+\.[0-9]+')
    break
  fi
  dir=$(dirname "$dir")
done

# Repo identity label — customize the case arms; fallback uses the repo name from the harness JSON (no `git remote get-url` subprocess). See README § Repo label badge.
clone_label=""
clone_color='\033[36m'
case "$cwd" in
  # */myorg/services*) clone_label="svc"; clone_color='\033[36m' ;;
  *) ;;
esac
if [ -z "$clone_label" ] && [ -n "$repo_name" ]; then
  clone_label="$repo_name"
fi

# Build parts
parts=()

if [ -n "$clone_label" ]; then
  parts+=("$(printf "${clone_color}[%s]\033[0m \033[2m%s\033[0m" "$clone_label" "$short_cwd")")
else
  parts+=("$(printf '\033[36m%s\033[0m' "$short_cwd")")
fi

[ -n "$git_branch" ] && parts+=("$(printf '\033[35m%s%s\033[0m' "$git_branch" "$git_dirty")")

# PR badge — native JSON fields for the CWD repo (no subprocess; colored by review state)
if [ -n "$pr_number" ]; then
  case "$pr_review_state" in
    approved)          pr_color='\033[32m' ;;
    changes_requested) pr_color='\033[31m' ;;
    draft)             pr_color='\033[33m' ;;
    *)                 pr_color='\033[32m' ;;   # open / pending review
  esac
  parts+=("$(printf "${pr_color}PR#%s\033[0m" "$pr_number")")
fi

# Secondary-repo PR badges read /tmp/claude-pr-cache-<repo>-<branch> (native JSON only covers the CWD repo's PR). See README § PR badge.
_pr_badge_cache() {
  local repo="$1" dir="$2"
  local branch
  branch=$(git -C "$dir" --no-optional-locks branch --show-current 2>/dev/null)
  [ -z "$branch" ] || [ "$branch" = "main" ] || [ "$branch" = "master" ] && return
  local safe cache pr_line pr_num pr_state
  safe=$(printf '%s' "$branch" | tr '/' '_' | tr ' ' '-')
  cache="/tmp/claude-pr-cache-${repo}-${safe}"
  [ -f "$cache" ] || return
  pr_line=$(cat "$cache")
  pr_num=$(printf '%s\n' "$pr_line" | awk '{print $1}')
  pr_state=$(printf '%s\n' "$pr_line" | awk '{print $2}')
  [ -z "$pr_num" ] && return
  local color
  case "$pr_state" in
    DRAFT)         color='\033[33m' ;;
    MERGED|CLOSED) color='\033[2m'  ;;
    *)             color='\033[32m' ;;
  esac
  printf "${color}%s:PR#%s\033[0m" "$repo" "$pr_num"
}

# Sibling repos to show PR badges for even when they're not the cwd:
secondary_repos=()
# secondary_repos=("$HOME/code/infrastructure" "$HOME/code/workflows")
for _rdir in "${secondary_repos[@]}"; do
  [ -d "$_rdir" ] || continue
  _repo=$(basename "$_rdir")
  [ "$_repo" = "$repo_name" ] && continue   # skip if this is the CWD repo
  _badge=$(_pr_badge_cache "$_repo" "$_rdir")
  [ -n "$_badge" ] && parts+=("$_badge")
done

# K8s context — red for prod, yellow for stg, dim for others
if [ -n "$k8s_context" ]; then
  case "$k8s_context" in
    *prod*) kcolor='\033[91m' ;;
    *stg*)  kcolor='\033[33m' ;;
    *)      kcolor='\033[2m'  ;;
  esac
  parts+=("$(printf "${kcolor}%s\033[0m" "$k8s_context")")
fi

# Terraform workspace — red for prod, yellow for stg, green for others
if [ -n "$tf_workspace" ]; then
  case "$tf_workspace" in
    *prod*)          tfcolor='\033[91m' ;;
    *stg*|*staging*) tfcolor='\033[33m' ;;
    *)               tfcolor='\033[32m' ;;
  esac
  parts+=("$(printf "${tfcolor}tf:%s\033[0m" "$tf_workspace")")
fi

[ -n "$aws_profile" ] && parts+=("$(printf '\033[33m%s\033[0m' "aws:$aws_profile")")
[ -n "$py_version" ]  && parts+=("$(printf '\033[2mpy:%s\033[0m' "$py_version")")

# Worktree: prefer --worktree session name, fall back to git worktree name
wt_display="${worktree_name:-$git_worktree}"
[ -n "$wt_display" ] && parts+=("$(printf '\033[2mwt:%s\033[0m' "$wt_display")")

# Session name — only when set via /rename
[ -n "$session_name" ] && parts+=("$(printf '\033[2m[%s]\033[0m' "$session_name")")

# Multi-root session signal — when --add-dir / /add-dir is active
[ -n "$added_dirs_count" ] && parts+=("$(printf '\033[2m+%sdirs\033[0m' "$added_dirs_count")")

[ -n "$model" ] && parts+=("$(printf '\033[2m%s\033[0m' "$model")")

# Effort level — only show non-default levels (high is treated as the default)
case "$effort_level" in
  max)    parts+=("$(printf '\033[31mmax\033[0m')")  ;;
  xhigh)  parts+=("$(printf '\033[31mxhg\033[0m')")  ;;
  low)    parts+=("$(printf '\033[2mlow\033[0m')")   ;;
  medium) parts+=("$(printf '\033[2mmed\033[0m')")   ;;
esac

# Extended thinking indicator
[ "$thinking_enabled" = "true" ] && parts+=("$(printf '\033[33mthink\033[0m')")

# Lines changed this session (zero-cost — from JSON, no subprocess)
if [ -n "$lines_added" ] || [ -n "$lines_removed" ]; then
  la="${lines_added:-0}"; lr="${lines_removed:-0}"
  parts+=("$(printf '\033[2m+%s/-%s\033[0m' "$la" "$lr")")
fi

# Context window usage
if [ -n "$used" ]; then
  used_int=$(echo "$used" | awk '{printf "%d", $1}')
  if   [ "$used_int" -ge 80 ]; then color='\033[31m'
  elif [ "$used_int" -ge 50 ]; then color='\033[33m'
  else                               color='\033[32m'
  fi
  parts+=("$(printf "${color}ctx:%d%%\033[0m" "$used_int")")
fi

# Rate limit (5-hour window) with reset countdown — only shown when approaching the limit
if [ -n "$rate5h" ]; then
  rl_int=$(echo "$rate5h" | awk '{printf "%d", $1}')
  if [ "$rl_int" -ge 50 ]; then
    rl_suffix=""
    if [ -n "$rl_resets_at" ]; then
      now=$(date '+%s')
      remaining_secs=$(( rl_resets_at - now ))
      if [ "$remaining_secs" -gt 0 ]; then
        remaining_min=$(( remaining_secs / 60 ))
        rl_suffix=" ${remaining_min}m"
      fi
    fi
    if [ "$rl_int" -ge 80 ]; then
      parts+=("$(printf '\033[31mrl:%d%%%s\033[0m' "$rl_int" "$rl_suffix")")
    else
      parts+=("$(printf '\033[33mrl:%d%%%s\033[0m' "$rl_int" "$rl_suffix")")
    fi
  fi
fi

printf '%s' "${parts[0]}"
for part in "${parts[@]:1}"; do
  printf ' \033[2m|\033[0m %s' "$part"
done
printf '\n'
