#!/usr/bin/env bash
# generate-inventory.sh — Regenerate agent-roster.md and skill-inventory.md from disk.
#
# Scans .claude/agents/, .claude/skills/, and subdirectory .claude/ directories.
# Extracts frontmatter fields (model, maxTurns, read-only, effort, user-invocable)
# and outputs regenerated markdown tables.
#
# Usage:
#   .claude/scripts/generate-inventory.sh [--dry-run]
#   --dry-run: print to stdout only, don't write files

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CLAUDE_DIR="$REPO_ROOT/.claude"
DRY_RUN=0
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Extract a frontmatter field value from a markdown file.
# Handles both inline values and YAML folded/literal block scalars (>- or |).
# Usage: _fm_field <file> <field>
_fm_field() {
  local file="$1" field="$2"
  awk '
    /^---/ { if(found++) exit; next }
    found {
      if ($0 ~ "^" field ":") {
        val = $0
        sub("^" field ":[[:space:]]*", "", val)
        if (val == ">-" || val == ">" || val == "|" || val == "|-") {
          # Multi-line block scalar — collect continuation lines
          getline
          while ($0 ~ /^[[:space:]]/) {
            sub(/^[[:space:]]+/, "", $0)
            line = $0
            if (result != "") result = result " "
            result = result line
            if (length(result) > 200) break
            getline
          }
          print result
        } else {
          print val
        }
        exit
      }
    }
  ' field="$field" "$file"
}

# Extract description from frontmatter or first non-heading content line.
_description() {
  local file="$1"
  local desc
  desc=$(_fm_field "$file" "description")
  if [[ -z "$desc" ]]; then
    desc=$(awk 'BEGIN{delim=0} /^---/{delim++;next} delim>=2 && /^#/{found_h=1;next} delim>=2 && found_h && /^[^#[:space:]]/{print;exit}' "$file" 2>/dev/null)
  fi
  desc="${desc#\"}" ; desc="${desc%\"}"
  desc="${desc#\'}" ; desc="${desc%\'}"
  desc="${desc//|/\\|}"
  # Truncate to 120 characters via python for cross-bash-version consistency.
  # bash 3.2 (macOS default) treats ${var:0:N} as bytes, bash 5.x as chars —
  # producing different output for descriptions with multi-byte UTF-8 (e.g. em-dash).
  python3 -c 'import sys; s = sys.argv[1]; sys.stdout.write(s[:120])' "$desc"; echo
}

# ---------------------------------------------------------------------------
# 1. Scan agents
# ---------------------------------------------------------------------------

# Parallel arrays keyed by index (bash 3.2 compatible — no associative arrays).
# AGENT_SCOPE[i] is the scope for AGENT_ROW[i]. Consumers iterate both and group
# by unique scope values on output.
declare -a AGENT_SCOPE=()
declare -a AGENT_ROW=()

_scan_agents() {
  local dir="$1" scope="${2:-repo-root}"
  local f name model max_turns effort desc notes

  while IFS= read -r -d '' f; do
    name=$(basename "$f" .md)
    [[ "$name" == "README" ]] && continue

    model=$(_fm_field "$f" "model")
    max_turns=$(_fm_field "$f" "maxTurns")
    effort=$(_fm_field "$f" "effort")
    desc=$(_description "$f")

    # Notes column: effort level (read-only is in description text, not a frontmatter field)
    notes="${effort:+effort: $effort}"

    AGENT_SCOPE+=("$scope")
    AGENT_ROW+=("| **$name** | ${desc} | ${model:-sonnet} | ${max_turns:-20} | ${notes} |")
  done < <(find "$dir" -maxdepth 1 -name '*.md' -not -name 'README*' -print0 2>/dev/null | sort -z)
}

_scan_agents "$CLAUDE_DIR/agents" "repo-root"

# Subdirectory agents
while IFS= read -r -d '' subdir; do
  rel_dir="${subdir#"$REPO_ROOT"/}"
  top_dir="${rel_dir%%/.claude/*}"
  _scan_agents "$subdir" "$top_dir"
done < <(find "$REPO_ROOT" -path "$REPO_ROOT/.claude/worktrees" -prune -o -path '*/.claude/agents' -not -path "$CLAUDE_DIR/agents" -type d -print0 2>/dev/null | sort -z)

# ---------------------------------------------------------------------------
# 2. Scan skills
# ---------------------------------------------------------------------------

declare -a SKILL_SCOPE=()
declare -a SKILL_TOPIC=()
declare -a SKILL_ROW=()

# Scan all SKILL.md files recursively under a skills directory.
# Only depth-1 skills (e.g., skills/pr-review/SKILL.md) are discovered by
# Claude Code — nested groupings are NOT loaded. The recursive find is kept
# so misplaced skills are still reported in the inventory and flagged.
_scan_skills() {
  local skills_root="$1" scope="${2:-repo-root}"
  local skill_file skill_dir name user_inv topic desc inv_str

  while IFS= read -r -d '' skill_file; do
    skill_dir="$(dirname "$skill_file")"
    name=$(basename "$skill_dir")
    user_inv=$(_fm_field "$skill_file" "user-invocable")
    topic=$(_fm_field "$skill_file" "topic")
    topic="${topic#\"}" ; topic="${topic%\"}"
    topic="${topic#\'}" ; topic="${topic%\'}"
    desc=$(_description "$skill_file")

    inv_str=""
    [[ "$user_inv" == "true" ]] && inv_str="✓"

    SKILL_SCOPE+=("$scope")
    SKILL_TOPIC+=("$topic")
    SKILL_ROW+=("| \`/$name\` | ${desc} | ${inv_str} |")
  done < <(find "$skills_root" -name 'SKILL.md' -print0 2>/dev/null | sort -z)
}

_scan_skills "$CLAUDE_DIR/skills" "repo-root"

# Subdirectory skills (other */.claude/skills/ trees, e.g., python/.claude/skills/)
while IFS= read -r -d '' skills_dir; do
  [[ "$skills_dir" == "$CLAUDE_DIR/skills" ]] && continue
  rel_dir="${skills_dir#"$REPO_ROOT"/}"
  top_dir="${rel_dir%%/.claude/*}"
  _scan_skills "$skills_dir" "$top_dir"
done < <(find "$REPO_ROOT" -path "$REPO_ROOT/.claude/worktrees" -prune -o -path '*/.claude/skills' -type d -print0 2>/dev/null | sort -z)

# ---------------------------------------------------------------------------
# 3. Generate output
# ---------------------------------------------------------------------------

# Canonical topic display order. Topics not listed here are emitted after,
# in first-seen order. Edit this list to match your project's skill taxonomy.
declare -a PREDEFINED_TOPICS=(
  "PR Management"
  "DevOps"
  "Evaluation & Tooling"
  "Learning & Knowledge"
)

# Re-order UNIQUE_TOPICS: predefined first (in order), then any remaining.
_sort_topics() {
  declare -a sorted=()
  local t p found
  for p in "${PREDEFINED_TOPICS[@]}"; do
    for t in "${UNIQUE_TOPICS[@]+"${UNIQUE_TOPICS[@]}"}"; do
      [[ "$t" == "$p" ]] && sorted+=("$t") && break
    done
  done
  for t in "${UNIQUE_TOPICS[@]+"${UNIQUE_TOPICS[@]}"}"; do
    found=0
    for p in "${PREDEFINED_TOPICS[@]}"; do
      [[ "$t" == "$p" ]] && found=1 && break
    done
    [[ $found -eq 0 ]] && sorted+=("$t")
    true
  done
  UNIQUE_TOPICS=("${sorted[@]+"${sorted[@]}"}")
  return 0
}

ROSTER_OUT="${ROSTER_OUT:-$CLAUDE_DIR/docs/agent-roster.md}"
INVENTORY_OUT="${INVENTORY_OUT:-$CLAUDE_DIR/docs/skill-inventory.md}"

_scope_heading() {
  case "$1" in
    repo-root) echo "Repo root (\`.claude/agents/\` and \`.claude/skills/\`)" ;;
    *)         echo "\`$1/.claude/\` — auto-loads when CWD is under \`$1/\`" ;;
  esac
}

# Collect unique scopes in first-seen order from a parallel array.
# Usage: _unique_scopes "${ARRAY[@]}" → sets UNIQUE_SCOPES
_unique_scopes() {
  UNIQUE_SCOPES=()
  local s seen
  for s in "$@"; do
    seen=0
    for existing in "${UNIQUE_SCOPES[@]:-}"; do
      [[ "$existing" == "$s" ]] && seen=1 && break
    done
    [[ $seen -eq 0 ]] && UNIQUE_SCOPES+=("$s")
    true
  done
  return 0
}

# Collect unique topics for a given scope in first-seen order.
# Sets UNIQUE_TOPICS. Skills without a topic field produce an empty string entry.
# Uses ${arr[@]+"${arr[@]}"} (not :-) so an empty array produces zero iterations,
# not a spurious empty-string element that falsely deduplicates no-topic skills.
# Returns 0 unconditionally so the bare call never triggers set -e.
_unique_topics_in_scope() {
  local scope="$1"
  UNIQUE_TOPICS=()
  local i t seen existing
  for i in "${!SKILL_SCOPE[@]}"; do
    [[ "${SKILL_SCOPE[$i]}" != "$scope" ]] && continue
    t="${SKILL_TOPIC[$i]}"
    seen=0
    for existing in "${UNIQUE_TOPICS[@]+"${UNIQUE_TOPICS[@]}"}"; do
      [[ "$existing" == "$t" ]] && seen=1 && break
    done
    [[ $seen -eq 0 ]] && UNIQUE_TOPICS+=("$t")
    true
  done
  return 0
}

ROSTER_CONTENT="# Agent Roster

Auto-generated by \`.claude/scripts/generate-inventory.sh\`. Do not edit manually.

For deferral rules between agents, read the **Sibling Agents** / **Deferral** section inside each agent's own file — they are authoritative and kept alongside the agent's prompt.

"
_unique_scopes "${AGENT_SCOPE[@]+"${AGENT_SCOPE[@]}"}"
for scope in "${UNIQUE_SCOPES[@]}"; do
  ROSTER_CONTENT+="## $(_scope_heading "$scope")

| Agent | Description | Model | Max Turns | Notes |
|-------|-------------|-------|-----------|-------|
"
  for i in "${!AGENT_SCOPE[@]}"; do
    [[ "${AGENT_SCOPE[$i]}" == "$scope" ]] && ROSTER_CONTENT+="${AGENT_ROW[$i]}
"
  done
  ROSTER_CONTENT+="
"
done

INVENTORY_CONTENT="# Skill Inventory

Auto-generated by \`.claude/scripts/generate-inventory.sh\`. Do not edit manually.

Skill descriptions below are truncated; the full description (and any \"When NOT to Use\" / disambiguation guidance for overlapping skills like \`/pr-check\` vs \`/pr-resolver\`) lives in each \`SKILL.md\` frontmatter and body. Claude routes on the frontmatter description, not this table.

"
_unique_scopes "${SKILL_SCOPE[@]+"${SKILL_SCOPE[@]}"}"
for scope in "${UNIQUE_SCOPES[@]}"; do
  INVENTORY_CONTENT+="## $(_scope_heading "$scope")

"
  _unique_topics_in_scope "$scope"
  _sort_topics
  has_topics=0
  for _t in "${UNIQUE_TOPICS[@]+"${UNIQUE_TOPICS[@]}"}"; do
    [[ -n "$_t" ]] && has_topics=1 && break
  done

  if [[ $has_topics -eq 1 ]]; then
    for topic in "${UNIQUE_TOPICS[@]}"; do
      if [[ -n "$topic" ]]; then
        INVENTORY_CONTENT+="### $topic

| Skill | Description | User-Invocable |
|-------|-------------|----------------|
"
      else
        INVENTORY_CONTENT+="### Other

| Skill | Description | User-Invocable |
|-------|-------------|----------------|
"
      fi
      for i in "${!SKILL_SCOPE[@]}"; do
        [[ "${SKILL_SCOPE[$i]}" == "$scope" && "${SKILL_TOPIC[$i]}" == "$topic" ]] && INVENTORY_CONTENT+="${SKILL_ROW[$i]}
"
      done
      INVENTORY_CONTENT+="
"
    done
  else
    INVENTORY_CONTENT+="| Skill | Description | User-Invocable |
|-------|-------------|----------------|
"
    for i in "${!SKILL_SCOPE[@]}"; do
      [[ "${SKILL_SCOPE[$i]}" == "$scope" ]] && INVENTORY_CONTENT+="${SKILL_ROW[$i]}
"
    done
    INVENTORY_CONTENT+="
"
  fi
done

if [[ $DRY_RUN -eq 1 ]]; then
  printf '\n=== agent-roster.md ===\n'
  echo "$ROSTER_CONTENT"
  printf '\n=== skill-inventory.md ===\n'
  echo "$INVENTORY_CONTENT"
else
  echo "$ROSTER_CONTENT" > "$ROSTER_OUT"
  echo "$INVENTORY_CONTENT" > "$INVENTORY_OUT"
  printf 'Updated: %s\n' "$ROSTER_OUT" "$INVENTORY_OUT"
fi
