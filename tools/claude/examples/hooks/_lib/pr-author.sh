#!/usr/bin/env bash
# Shared PR-authorship and repo-visibility predicates, for hooks that gate on who wrote a PR.
# see: tools/claude/examples/hooks/_lib/README.md § pr-author.sh — cache layout, TTLs, and the fail-closed contract

PR_AUTHOR_CACHE="${HOME}/.claude/local/pr-author-cache.tsv"
PR_SELF_CACHE="${HOME}/.claude/local/gh-self-login"
REPO_VIS_CACHE="${HOME}/.claude/local/repo-visibility.tsv"
REPO_VIS_TTL=604800     # 7d — authorship never changes, visibility does; a stale PRIVATE grants on a repo since made public
REPO_VIS_FAIL_TTL=3600  # 1h — cache failures too, or an unresolvable repo pays a fresh round-trip per command

# Never inferred from the cwd: a `cd` earlier in the same command moves what gh would pick.
gh_repo_target() {
  local tok
  tok=$(printf '%s' "$1" | grep -oE '(^|[^A-Za-z0-9_-])repos/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+' \
        | head -1 | sed -E 's|.*repos/||')
  [ -n "$tok" ] || tok=$(printf '%s' "$1" | sed -nE 's/.*--repo[=[:space:]]+"?([^"[:space:]]+).*/\1/p' | head -1)
  printf '%s' "$tok" | grep -qE '^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$' || return 1
  printf '%s' "$tok"
}

# A FAILED lookup is cached as UNKNOWN on the short TTL, so a transient network error cannot stick for a week.
repo_visibility() {
  local repo=$1 line vis ts age to=""
  printf '%s' "$repo" | grep -qE '^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$' || return 1
  line=$(grep -F "${repo}	" "$REPO_VIS_CACHE" 2>/dev/null | tail -1)
  if [ -n "$line" ]; then
    ts=${line##*	}
    case "$ts" in ''|*[!0-9]*) ts=0 ;; esac
    vis=${line#*	}; vis=${vis%%	*}
    age=$(( $(date +%s) - ts ))
    if [ "$vis" = UNKNOWN ]; then
      [ "$age" -lt "$REPO_VIS_FAIL_TTL" ] && return 1
    elif [ "$age" -lt "$REPO_VIS_TTL" ]; then
      printf '%s' "$vis"; return 0
    fi
  fi
  mkdir -p "${HOME}/.claude/local"
  if command -v gh >/dev/null 2>&1; then
    command -v timeout >/dev/null 2>&1 && to="timeout 8"
    vis=$($to gh repo view "$repo" --json visibility --jq .visibility 2>/dev/null)
  else
    vis=""
  fi
  [ -n "$vis" ] || vis=UNKNOWN
  printf '%s\t%s\t%s\n' "$repo" "$vis" "$(date +%s)" >> "$REPO_VIS_CACHE"
  [ "$vis" = UNKNOWN ] && return 1
  printf '%s' "$vis"
}

# The owner is not a proxy: an org carrying both public and private repos would grant on exactly the class excluded.
repo_is_internal() {
  local vis
  vis=$(repo_visibility "$1") || return 1
  case "$vis" in PRIVATE|INTERNAL) return 0 ;; esac
  return 1
}

# Emits "<is_bot>|<login>" for a literal (repo, number), or nothing when it cannot be resolved.
pr_author_lookup() {
  local repo=$1 num=$2 line verdict to=""
  command -v gh >/dev/null 2>&1 || return 1
  command -v timeout >/dev/null 2>&1 && to="timeout 8"
  line=$(grep -F "${repo}	${num}	" "$PR_AUTHOR_CACHE" 2>/dev/null | head -1)
  if [ -n "$line" ]; then
    printf '%s' "${line##*	}"
    return 0
  fi
  verdict=$($to gh pr view "$num" --repo "$repo" --json author \
    --jq '"\(.author.is_bot)|\(.author.login)"' 2>/dev/null)
  [ -n "$verdict" ] || return 1
  mkdir -p "${HOME}/.claude/local"
  printf '%s\t%s\t%s\n' "$repo" "$num" "$verdict" >> "$PR_AUTHOR_CACHE"
  printf '%s' "$verdict"
}

pr_self_login() {
  local self to=""
  self=$(cat "$PR_SELF_CACHE" 2>/dev/null)
  if [ -z "$self" ]; then
    command -v timeout >/dev/null 2>&1 && to="timeout 8"
    self=$($to gh api user --jq .login 2>/dev/null)
    # Siblings create this dir before writing; without it the redirect fails and nothing is ever cached.
    mkdir -p "${HOME}/.claude/local"
    [ -n "$self" ] && printf '%s\n' "$self" > "$PR_SELF_CACHE"
  fi
  printf '%s' "$self"
}

# `--repo` is required rather than inferred — resolving the number against the wrong repo is how this fails OPEN.
pr_review_target() {
  local seg=$1 num tok
  num=$(printf '%s' "$seg" | sed -E 's/.*pr[[:space:]]+review//' \
    | tr ' ' '\n' | grep -m1 -xE '[0-9]+')
  [ -n "$num" ] || return 1
  tok=$(printf '%s' "$seg" | sed -nE 's/.*--repo[=[:space:]]+"?([^"[:space:]]+).*/\1/p' | head -1)
  printf '%s' "$tok" | grep -qE '^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$' || return 1
  printf '%s\t%s' "$tok" "$num"
}

# True for a bot- or self-authored PR. Every unresolvable input returns false, so this fails closed.
pr_review_author_is_exempt() {
  local target repo num verdict self
  [ "${PR_AUTHOR_LOOKUP:-1}" = "1" ] || return 1
  target=$(pr_review_target "$1") || return 1
  repo=${target%%	*}
  num=${target##*	}
  verdict=$(pr_author_lookup "$repo" "$num") || return 1
  case "$verdict" in true\|*) return 0 ;; esac
  self=$(pr_self_login)
  [ -n "$self" ] && [ "${verdict#*|}" = "$self" ] && return 0
  return 1
}

# True only for a self-authored PR — the narrower class, for gates bots must not clear.
pr_review_author_is_self() {
  local target repo num verdict self
  [ "${PR_AUTHOR_LOOKUP:-1}" = "1" ] || return 1
  target=$(pr_review_target "$1") || return 1
  repo=${target%%	*}
  num=${target##*	}
  verdict=$(pr_author_lookup "$repo" "$num") || return 1
  self=$(pr_self_login)
  [ -n "$self" ] && [ "${verdict#*|}" = "$self" ] && return 0
  return 1
}
