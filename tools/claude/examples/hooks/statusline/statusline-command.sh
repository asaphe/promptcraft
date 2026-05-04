#!/usr/bin/env bash
# Claude Code statusline — dir | branch | pr | k8s | tf | aws | py | wt | model | ctx | rl | cost
#
# Segments (all conditional except dir):
#   [label] ~/path     — repo label badge; falls back to git remote name for worktrees
#   branch*            — git branch with dirty indicator
#   PR#123             — open PR for current branch (requires pr-context-inject cache)
#   k8s-context        — kubectl context (red=prod, yellow=stg)
#   tf:workspace       — Terraform workspace (only when .terraform/environment found)
#   aws:profile        — AWS_PROFILE env var, if set
#   py:3.12            — pyenv version (major.minor, only when .python-version found)
#   wt:name            — active worktree name (only when in a worktree)
#   model-name         — active Claude model (dim)
#   ctx:42%            — context window usage (green <50%, yellow <80%, red ≥80%)
#   rl:62%             — 5-hour rate limit (only shown ≥50%; yellow, red ≥80%)
#   $0.12              — session cost (dim <$1, yellow $1-$5, red ≥$5)

input=$(cat)

IFS=$(printf '\t') read -r model used cost rate5h worktree_name < <(echo "$input" | jq -r '[
  (.model.display_name // ""),
  (.context_window.used_percentage // ""),
  (.cost.total_cost_usd // ""),
  (.rate_limits.five_hour.used_percentage // ""),
  (.worktree.name // "")
] | @tsv')

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

# Repo identity label — fixed badge for known repos, git remote name for everything else.
# Customize the case arms for your own layout; the fallback handles worktrees in /tmp
# and unknown repos automatically.
clone_label=""
clone_color='\033[36m'
case "$cwd" in
  # Uncomment and adapt:
  # */myorg/services*)       clone_label="svc";   clone_color='\033[36m' ;;
  # */myorg/infrastructure*) clone_label="infra"; clone_color='\033[93m' ;;
  # */.dotfiles*)            clone_label="dots";  clone_color='\033[97m' ;;
  *) ;;
esac
if [ -z "$clone_label" ]; then
  _remote=$(git -C "$cwd" remote get-url origin 2>/dev/null | sed 's|.*/||; s|\.git$||')
  [ -n "$_remote" ] && clone_label="$_remote"
fi

# PR badge — reads from a repo+branch-scoped cache file written by a pr-context-inject
# hook. No cache file = no badge (no API call on every tick).
_pr_badge() {
  local repo="$1" dir="$2"
  local branch
  branch=$(git -C "$dir" --no-optional-locks branch --show-current 2>/dev/null)
  [ -z "$branch" ] || [ "$branch" = "main" ] || [ "$branch" = "master" ] && return
  local safe
  safe=$(printf '%s' "$branch" | tr '/' '_' | tr ' ' '-')
  local cache="/tmp/claude-pr-cache-${repo}-${safe}"
  [ -f "$cache" ] || return
  local pr_line pr_num pr_state
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

# Build parts
parts=()

if [ -n "$clone_label" ]; then
  parts+=("$(printf "${clone_color}[%s]\033[0m \033[2m%s\033[0m" "$clone_label" "$short_cwd")")
else
  parts+=("$(printf '\033[36m%s\033[0m' "$short_cwd")")
fi

[ -n "$git_branch" ] && parts+=("$(printf '\033[35m%s%s\033[0m' "$git_branch" "$git_dirty")")

# PR badge for CWD repo (no repo prefix — implied by label)
if [ -n "$git_branch" ] && [ "$git_branch" != "main" ] && [ "$git_branch" != "master" ]; then
  _cwd_repo=$(git remote get-url origin 2>/dev/null | sed 's|.*/||' | sed 's|\.git$||')
  if [ -n "$_cwd_repo" ]; then
    _safe=$(printf '%s' "$git_branch" | tr '/' '_' | tr ' ' '-')
    _cache="/tmp/claude-pr-cache-${_cwd_repo}-${_safe}"
    if [ -f "$_cache" ]; then
      _pr_line=$(cat "$_cache")
      _pr_num=$(printf '%s\n' "$_pr_line" | awk '{print $1}')
      _pr_state=$(printf '%s\n' "$_pr_line" | awk '{print $2}')
      if [ -n "$_pr_num" ]; then
        case "$_pr_state" in
          DRAFT)         _pr_color='\033[33m' ;;
          MERGED|CLOSED) _pr_color='\033[2m'  ;;
          *)             _pr_color='\033[32m' ;;
        esac
        parts+=("$(printf "${_pr_color}PR#%s\033[0m" "$_pr_num")")
      fi
    fi
  fi
fi

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
[ -n "$worktree_name" ] && parts+=("$(printf '\033[2mwt:%s\033[0m' "$worktree_name")")
[ -n "$model" ]       && parts+=("$(printf '\033[2m%s\033[0m' "$model")")

if [ -n "$used" ]; then
  used_int=$(echo "$used" | awk '{printf "%d", $1}')
  if   [ "$used_int" -ge 80 ]; then color='\033[31m'
  elif [ "$used_int" -ge 50 ]; then color='\033[33m'
  else                               color='\033[32m'
  fi
  parts+=("$(printf "${color}ctx:%d%%\033[0m" "$used_int")")
fi

# Rate limit (5-hour window) — only shown when approaching the limit
if [ -n "$rate5h" ]; then
  rl_int=$(echo "$rate5h" | awk '{printf "%d", $1}')
  if   [ "$rl_int" -ge 80 ]; then
    parts+=("$(printf '\033[31mrl:%d%%\033[0m' "$rl_int")")
  elif [ "$rl_int" -ge 50 ]; then
    parts+=("$(printf '\033[33mrl:%d%%\033[0m' "$rl_int")")
  fi
fi

# Session cost — dim below $1, yellow $1-$5, red ≥$5
if [ -n "$cost" ] && [ "$cost" != "0" ]; then
  cost_cents=$(echo "$cost" | awk '{printf "%d", $1 * 100}')
  if   [ "$cost_cents" -ge 500 ]; then ccolor='\033[31m'
  elif [ "$cost_cents" -ge 100 ]; then ccolor='\033[33m'
  else                                  ccolor='\033[2m'
  fi
  parts+=("$(printf "${ccolor}\$%.2f\033[0m" "$cost")")
fi

printf '%s' "${parts[0]}"
for part in "${parts[@]:1}"; do
  printf ' \033[2m|\033[0m %s' "$part"
done
printf '\n'
