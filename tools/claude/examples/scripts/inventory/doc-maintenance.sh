#!/usr/bin/env bash
# doc-maintenance.sh — Validate .claude/ doc health across the services repo.
#
# Phase 1: three checks:
#   1. Path validation    — backtick-quoted .claude/ paths in docs resolve to real files
#   2. Inventory sync     — agent-roster.md and skill-inventory.md match actual files on disk
#   3. Cross-ref check    — CLAUDE.md agent refs, skill doc refs, hook paths in settings.json
#
# Usage:
#   .claude/scripts/doc-maintenance.sh [--fix]   (--fix not yet implemented)
#
# Exit codes: 0 = all clean, 1 = issues found (non-blocking), 2 = script error

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CLAUDE_DIR="$REPO_ROOT/.claude"
ERRORS=0
WARNINGS=0

_pass()  { printf '  \033[32m✓\033[0m %s\n' "$*"; }
_warn()  { printf '  \033[33m⚠\033[0m %s\n' "$*"; WARNINGS=$((WARNINGS+1)); }
_fail()  { printf '  \033[31m✗\033[0m %s\n' "$*"; ERRORS=$((ERRORS+1)); }
_section() { printf '\n\033[1m%s\033[0m\n' "$*"; }

# ---------------------------------------------------------------------------
# 1. Path validation: backtick-quoted .claude/ paths in docs
# ---------------------------------------------------------------------------
_section "1. Path validation"

PATHS_CHECKED=0
PATHS_MISSING=0

# Check only .claude/-prefixed path references — internal cross-references
# (skills referencing docs, agents referencing rules, etc.) are the most likely
# to go stale when files are renamed or moved.
# SC2016: backtick chars in the grep pattern are literals matching markdown, not expansions.
# shellcheck disable=SC2016
while IFS= read -r -d '' f; do
  while IFS= read -r token; do
    [[ -z "$token" ]] && continue
    # Skip template placeholders like {domain}, {tenant}
    [[ "$token" == *"{"* ]] && continue
    # Skip glob patterns (contain *)
    [[ "$token" == *"*"* ]] && continue
    # Skip path traversal attempts (.. segments escape repo root, producing false negatives)
    [[ "$token" == *".."* ]] && continue
    PATHS_CHECKED=$((PATHS_CHECKED+1))
    if [[ ! -e "$REPO_ROOT/$token" ]]; then
      _fail "Missing .claude/ path: \`$token\` in ${f#"$REPO_ROOT"/}"
      PATHS_MISSING=$((PATHS_MISSING+1))
    fi
  done < <(grep -oE '`\.claude/[^` ]+`' "$f" 2>/dev/null | sed 's/^`//; s/`$//')
done < <(find "$CLAUDE_DIR" -name '*.md' -print0)

if [[ $PATHS_MISSING -eq 0 ]]; then
  _pass "All $PATHS_CHECKED .claude/ path references resolved"
else
  # Use printf directly — individual _fail calls already incremented ERRORS
  printf '  \033[31m✗\033[0m %s\n' "$PATHS_MISSING of $PATHS_CHECKED .claude/ path references are missing"
fi

# ---------------------------------------------------------------------------
# 1b. Skill depth validation — Claude Code's loader only discovers
#     {skills_root}/{name}/SKILL.md. Any SKILL.md at depth >= 3 is invisible.
# ---------------------------------------------------------------------------
_section "1b. Skill depth (loader constraint)"

DEPTH_VIOLATIONS=0
while IFS= read -r -d '' skills_root; do
  while IFS= read -r -d '' skill_file; do
    rel="${skill_file#"$skills_root/"}"
    slashes="${rel//[^\/]/}"
    if (( ${#slashes} > 1 )); then
      _fail "SKILL.md at invalid depth (>=3): ${skill_file#"$REPO_ROOT"/} — must be at {skills_root}/{name}/SKILL.md"
      DEPTH_VIOLATIONS=$((DEPTH_VIOLATIONS+1))
    fi
  done < <(find "$skills_root" -name 'SKILL.md' -print0 2>/dev/null)
done < <(find "$REPO_ROOT" -path '*/.claude/worktrees/*' -prune -o -path '*/.claude/skills' -type d -print0 2>/dev/null)

if [[ $DEPTH_VIOLATIONS -eq 0 ]]; then
  _pass "All SKILL.md files at valid depth"
fi

# ---------------------------------------------------------------------------
# 2. Inventory validation
# ---------------------------------------------------------------------------
_section "2. Inventory sync"

ROSTER="$CLAUDE_DIR/docs/agent-roster.md"
INVENTORY="$CLAUDE_DIR/docs/skill-inventory.md"

# Agents on disk (repo-root .claude/agents/)
DISK_AGENTS=()
while IFS= read -r -d '' f; do
  name="$(basename "$f" .md)"
  DISK_AGENTS+=("$name")
done < <(find "$CLAUDE_DIR/agents" -maxdepth 1 -name '*.md' -not -name 'README*' -print0 2>/dev/null)

# Subdirectory agents (other */.claude/agents/)
while IFS= read -r -d '' f; do
  name="$(basename "$f" .md)"
  DISK_AGENTS+=("$name")
done < <(find "$REPO_ROOT" -path '*/.claude/worktrees/*' -prune -o -path '*/.claude/agents/*.md' -not -path "$CLAUDE_DIR/agents/*" -not -name 'README*' -print0 2>/dev/null)

# Check each disk agent appears in roster
if [[ -f "$ROSTER" ]]; then
  AGENTS_MISSING=0
  for agent in "${DISK_AGENTS[@]}"; do
    # Exact match: roster uses **bold** format for agent names
    if ! grep -qF "**${agent}**" "$ROSTER" 2>/dev/null; then
      _fail "Agent '$agent' not in agent-roster.md"
      AGENTS_MISSING=$((AGENTS_MISSING+1))
    fi
  done
  # Check roster doesn't have phantom entries — match **bold** agent name format
  while IFS= read -r line; do
    if [[ "$line" =~ \|[[:space:]]*\*\*([[:alpha:]][[:alnum:]_-]+)\*\* ]]; then
      roster_agent="${BASH_REMATCH[1]}"
      found=0
      for disk_agent in "${DISK_AGENTS[@]}"; do
        [[ "$disk_agent" == "$roster_agent" ]] && found=1 && break
      done
      [[ $found -eq 0 ]] && _warn "Roster entry '$roster_agent' has no matching agent file (phantom)"
    fi
  done < "$ROSTER"
  if [[ $AGENTS_MISSING -eq 0 ]]; then
    _pass "agent-roster.md checked against ${#DISK_AGENTS[@]} agent files"
  else
    printf '  \033[31m✗\033[0m %s\n' "$AGENTS_MISSING of ${#DISK_AGENTS[@]} agents missing from agent-roster.md"
  fi
else
  _warn "agent-roster.md not found at $ROSTER"
fi

# Skills on disk — scan all SKILL.md files recursively under .claude/skills/.
# Skills must live at depth 1 (e.g., .claude/skills/pr-review/SKILL.md) to be
# discovered by Claude Code — nested groupings are NOT loaded. See
# .claude/rules/claude-code-config-layout.md.
DISK_SKILLS=()
while IFS= read -r -d '' skill_file; do
  name="$(basename "$(dirname "$skill_file")")"
  DISK_SKILLS+=("$name")
done < <(find "$CLAUDE_DIR/skills" -name 'SKILL.md' -print0 2>/dev/null)

# Subdirectory skills (other */.claude/skills/ trees outside main .claude/skills/)
# Enumerate .claude/skills/ directories to stay scoped to .claude content,
# mirroring generate-inventory.sh's strategy exactly.
while IFS= read -r -d '' skills_dir; do
  [[ "$skills_dir" == "$CLAUDE_DIR/skills" ]] && continue
  while IFS= read -r -d '' skill_file; do
    name="$(basename "$(dirname "$skill_file")")"
    DISK_SKILLS+=("$name")
  done < <(find "$skills_dir" -name 'SKILL.md' -print0 2>/dev/null)
done < <(find "$REPO_ROOT" -path '*/.claude/worktrees/*' -prune -o -path '*/.claude/skills' -type d -print0 2>/dev/null)

if [[ -f "$INVENTORY" ]]; then
  BT='`'  # literal backtick — inventory uses `/$skill` format
  SKILLS_MISSING=0
  for skill in "${DISK_SKILLS[@]}"; do
    # Exact match: inventory uses `/skill-name` backtick-quoted format
    if ! grep -qF "${BT}/${skill}${BT}" "$INVENTORY" 2>/dev/null; then
      _fail "Skill '$skill' not in skill-inventory.md"
      SKILLS_MISSING=$((SKILLS_MISSING+1))
    fi
  done
  if [[ $SKILLS_MISSING -eq 0 ]]; then
    _pass "skill-inventory.md checked against ${#DISK_SKILLS[@]} skill directories"
  else
    printf '  \033[31m✗\033[0m %s\n' "$SKILLS_MISSING of ${#DISK_SKILLS[@]} skills missing from skill-inventory.md"
  fi
else
  _warn "skill-inventory.md not found at $INVENTORY"
fi

# 2b. Content equality — regenerate to temp files and diff against committed.
_section "2b. Inventory content equality"
GEN_SCRIPT="$CLAUDE_DIR/scripts/generate-inventory.sh"
if [[ -x "$GEN_SCRIPT" || -f "$GEN_SCRIPT" ]]; then
  GEN_TMPDIR=$(mktemp -d)
  trap 'rm -rf "$GEN_TMPDIR"' EXIT
  ROSTER_OUT="$GEN_TMPDIR/agent-roster.md" INVENTORY_OUT="$GEN_TMPDIR/skill-inventory.md" \
    bash "$GEN_SCRIPT" >/dev/null 2>&1 || true
  CONTENT_DRIFT=0
  GEN_RAN=0
  if [[ -f "$GEN_TMPDIR/agent-roster.md" && -f "$GEN_TMPDIR/skill-inventory.md" ]]; then
    GEN_RAN=1
  fi
  if [[ $GEN_RAN -eq 0 ]]; then
    _fail "generate-inventory.sh did not produce output — cannot verify content equality"
  else
    if [[ -f "$ROSTER" ]]; then
      if ! diff -q "$GEN_TMPDIR/agent-roster.md" "$ROSTER" >/dev/null 2>&1; then
        _fail "agent-roster.md content differs from generate-inventory.sh output — run the generator"
        diff -u "$ROSTER" "$GEN_TMPDIR/agent-roster.md" | head -30 >&2 || true
        CONTENT_DRIFT=1
      fi
    fi
    if [[ -f "$INVENTORY" ]]; then
      if ! diff -q "$GEN_TMPDIR/skill-inventory.md" "$INVENTORY" >/dev/null 2>&1; then
        _fail "skill-inventory.md content differs from generate-inventory.sh output — run the generator"
        diff -u "$INVENTORY" "$GEN_TMPDIR/skill-inventory.md" | head -30 >&2 || true
        CONTENT_DRIFT=1
      fi
    fi
    if [[ $CONTENT_DRIFT -eq 0 ]]; then
      _pass "Inventory files match regenerated output"
    fi
  fi
else
  _warn "generate-inventory.sh not found at $GEN_SCRIPT"
fi

# ---------------------------------------------------------------------------
# 3. Cross-reference validation
# ---------------------------------------------------------------------------
_section "3. Cross-reference checks"
CROSSREF_ERRORS_BEFORE=$ERRORS
CROSSREF_WARNINGS_BEFORE=$WARNINGS

# 3a. Hook scripts referenced in settings.json
SETTINGS="$CLAUDE_DIR/settings.json"
if [[ -f "$SETTINGS" ]]; then
  HOOK_ERRORS_BEFORE=$ERRORS
  # Extract full command strings, substitute $CLAUDE_PROJECT_DIR and $HOME
  while IFS= read -r cmd; do
    [[ -z "$cmd" || "$cmd" != *".sh"* ]] && continue
    resolved="$cmd"
    resolved="${resolved//\$CLAUDE_PROJECT_DIR/$REPO_ROOT}"
    resolved="${resolved//\$HOME/$HOME}"
    resolved="${resolved//\"/}"
    script_path=$(echo "$resolved" | grep -oE '[^ ]+\.sh' | head -1)
    if [[ -n "$script_path" && ! -f "$script_path" ]]; then
      _fail "Hook script not found: $script_path"
    fi
  done < <(jq -r '.. | objects | .command? // empty' "$SETTINGS" 2>/dev/null)
  if [[ $ERRORS -eq $HOOK_ERRORS_BEFORE ]]; then
    _pass "settings.json hook script paths checked"
  fi
fi

# 3b. CLAUDE.md @-includes resolve
CLAUDE_MD="$CLAUDE_DIR/CLAUDE.md"
if [[ -f "$CLAUDE_MD" ]]; then
  while IFS= read -r include; do
    path="${include#@}"
    if [[ ! -f "$REPO_ROOT/$path" ]]; then
      _fail "@include in CLAUDE.md not found: $path"
    fi
  done < <(grep -oE '@[^ ]+\.md' "$CLAUDE_MD" 2>/dev/null || true)
fi

# 3c. Skill SKILL.md files reference docs that exist (warnings only)
# Covers main .claude/skills/ and all subdirectory .claude/skills/ trees.
while IFS= read -r -d '' skills_root; do
  while IFS= read -r -d '' skill_file; do
    skill_name="$(basename "$(dirname "$skill_file")")"
    while IFS= read -r line; do
      while [[ "$line" =~ \`([^\`]+\.md)\` ]]; do
        ref="${BASH_REMATCH[1]}"
        line="${line#*\`"${ref}"\`}"
        [[ "$ref" == http* || "$ref" == *" "* || "$ref" == *"{"* || "$ref" == *"*"* ]] && continue
        if [[ ! -f "$REPO_ROOT/$ref" ]]; then
          _warn "Skill '$skill_name' references missing doc: \`$ref\`"
        fi
      done
    done < "$skill_file"
  done < <(find "$skills_root" -name 'SKILL.md' -print0 2>/dev/null)
done < <(find "$REPO_ROOT" -path '*/.claude/worktrees/*' -prune -o -path '*/.claude/skills' -type d -print0 2>/dev/null)

if [[ $ERRORS -eq $CROSSREF_ERRORS_BEFORE && $WARNINGS -eq $CROSSREF_WARNINGS_BEFORE ]]; then
  _pass "Cross-reference checks complete"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
printf '\n'
if [[ $ERRORS -gt 0 || $WARNINGS -gt 0 ]]; then
  printf '\033[1mResult:\033[0m %d error(s), %d warning(s)\n' "$ERRORS" "$WARNINGS"
  [[ $ERRORS -gt 0 ]] && exit 1
  exit 0
else
  printf '\033[32m\033[1mAll checks passed.\033[0m\n'
  exit 0
fi
