#!/usr/bin/env bash
# Claude Code statusline — mirrors p10k left prompt: dir | aws | model | context

input=$(cat)

cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // ""')
model=$(echo "$input" | jq -r '.model.display_name // ""')
used=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
aws_profile="${AWS_PROFILE:-${AWS_DEFAULT_PROFILE:-}}"

# Shorten home directory to ~
home="$HOME"
short_cwd="${cwd/#$home/~}"

# Git branch for the cwd
git_branch=""
if git_branch_raw=$(git -C "$cwd" --no-optional-locks branch --show-current 2>/dev/null); then
  git_branch="$git_branch_raw"
fi

# Build parts
parts=()

# Directory segment (cyan)
parts+=("$(printf '\033[36m%s\033[0m' "$short_cwd")")

# Git branch segment (magenta), if inside a repo
if [ -n "$git_branch" ]; then
  parts+=("$(printf '\033[35m%s\033[0m' "$git_branch")")
fi

# AWS profile segment (yellow), if set
if [ -n "$aws_profile" ]; then
  parts+=("$(printf '\033[33m%s\033[0m' "aws:$aws_profile")")
fi

# Model segment (dim)
if [ -n "$model" ]; then
  parts+=("$(printf '\033[2m%s\033[0m' "$model")")
fi

# Context window usage segment
if [ -n "$used" ]; then
  used_int=$(echo "$used" | awk '{printf "%d", $1}')
  if [ "$used_int" -ge 80 ]; then
    color='\033[31m'  # red
  elif [ "$used_int" -ge 50 ]; then
    color='\033[33m'  # yellow
  else
    color='\033[32m'  # green
  fi
  parts+=("$(printf "${color}ctx:%d%%\033[0m" "$used_int")")
fi

# Join with separator
printf '%s' "${parts[0]}"
for part in "${parts[@]:1}"; do
  printf ' \033[2m|\033[0m %s' "$part"
done
printf '\n'
