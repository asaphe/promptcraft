#!/usr/bin/env bash
# Claude Code statusline — dir | branch | k8s | tf | aws | py | model | ctx
#
# Segments shown (all conditional except dir):
#   [repo-label] ~/path   — colored badge when cwd matches a known repo (optional)
#   branch*               — git branch with dirty indicator (* = uncommitted changes)
#   k8s-context           — current kubectl context (red=prod, yellow=stg)
#   tf:workspace          — terraform workspace (only when .terraform/environment found)
#   aws:profile           — AWS_PROFILE env var, if set
#   py:3.12               — pyenv version (only when .python-version found, major.minor)
#   model-name            — active Claude model (dim)
#   ctx:42%               — context window usage (green <50%, yellow <80%, red ≥80%)

input=$(cat)

read -r model used < <(echo "$input" | jq -r '[
  (.model.display_name // ""),
  (.context_window.used_percentage // "")
] | @tsv')

cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // ""')
aws_profile="${AWS_PROFILE:-${AWS_DEFAULT_PROFILE:-}}"
home="$HOME"
short_cwd="${cwd/#$home/~}"

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
  k8s_context=$(grep 'current-context:' "$kubeconfig" 2>/dev/null | awk '{print $2}' | head -1)
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

# Repo identity labels — customize for your own layout.
# Useful in monorepos or multi-clone setups where path alone isn't enough context.
# Each matching branch sets clone_label (badge text) and clone_color (ANSI escape).
clone_label=""
clone_color='\033[36m'
case "$cwd" in
  # Uncomment and adapt for your repo structure:
  # */myorg/services*)    clone_label="svc";    clone_color='\033[36m'  ;;
  # */myorg/infrastructure*) clone_label="infra"; clone_color='\033[93m' ;;
  # */.dotfiles*)         clone_label="dotfiles"; clone_color='\033[97m' ;;
  *) ;;
esac

# Build parts
parts=()

if [ -n "$clone_label" ]; then
  parts+=("$(printf "${clone_color}[%s]\033[0m \033[2m%s\033[0m" "$clone_label" "$short_cwd")")
else
  parts+=("$(printf '\033[36m%s\033[0m' "$short_cwd")")
fi

[ -n "$git_branch" ] && parts+=("$(printf '\033[35m%s%s\033[0m' "$git_branch" "$git_dirty")")

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

[ -n "$py_version" ] && parts+=("$(printf '\033[2mpy:%s\033[0m' "$py_version")")

[ -n "$model" ] && parts+=("$(printf '\033[2m%s\033[0m' "$model")")

if [ -n "$used" ]; then
  used_int=$(echo "$used" | awk '{printf "%d", $1}')
  if   [ "$used_int" -ge 80 ]; then color='\033[31m'
  elif [ "$used_int" -ge 50 ]; then color='\033[33m'
  else                               color='\033[32m'
  fi
  parts+=("$(printf "${color}ctx:%d%%\033[0m" "$used_int")")
fi

printf '%s' "${parts[0]}"
for part in "${parts[@]:1}"; do
  printf ' \033[2m|\033[0m %s' "$part"
done
printf '\n'
