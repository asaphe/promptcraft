# Stale Reference Detection

Validates that file references in `.claude/` documentation point to files that actually exist. Catches broken links before they mislead future sessions.

## The problem

When a rule or doc file is deleted or renamed, any references to it in other `.claude/` files become stale. These stale references silently mislead — an agent reading "see `path/to/deleted-file.md`" wastes time looking for something that doesn't exist.

## Two modes

### Quick mode (`--deleted-only`)

Checks only files deleted in the current branch vs `origin/main`. Fast enough for pre-push hooks.

```bash
./check-stale-refs.sh --deleted-only
```

### Full scan mode (no arguments)

Scans all backtick-quoted file paths in `.claude/` markdown files against the filesystem. Use for periodic audits.

```bash
./check-stale-refs.sh
```

## Integration with pre-push hook

Add the `--deleted-only` check to an existing pre-push lint guard:

```bash
# In your pre-push hook, after linter checks:
DELETED_MD=$(echo "$CHANGED_FILES" | grep -E '\.md$' || true)
if [ -n "$DELETED_MD" ]; then
  for f in $DELETED_MD; do
    if [ ! -f "$REPO_ROOT/$f" ]; then
      base=$(basename "$f")
      refs=$(grep -rlF "$base" "$REPO_ROOT/.claude/" 2>/dev/null | grep -vF '.git' || true)
      if [ -n "$refs" ]; then
        FAILURES="${FAILURES}\n\n### Stale reference: deleted '$base' still referenced"
      fi
    fi
  done
fi
```

## What it catches

- Deleted rule files still listed in README directory trees
- Deleted docs still referenced by on-demand pointers in CLAUDE.md
- Renamed files where the old name is still used in agent definitions
- Merged files (e.g., `file-a.md` and `file-b.md` combined into `file-c.md`) where old names linger

## Layer

**Project** (`.claude/hooks/`) — repo-specific validation, committed with the repo.
