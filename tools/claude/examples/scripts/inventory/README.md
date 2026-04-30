# `.claude/` inventory and maintenance scripts

> **When this fits:** these scripts assume your repo has multiple `.claude/` trees (a repo-root `.claude/` plus subdirectory ones like `python/.claude/`, `.github/.claude/`), and that you treat `.claude/docs/agent-roster.md` and `.claude/docs/skill-inventory.md` as the canonical inventory artifacts. They expect specific frontmatter fields (`description`, `model`, `maxTurns`, `topic`, `user-invocable`). If your `.claude/` is a single tree without auto-generated inventory docs, you don't need these.

Two scripts that keep `.claude/` config healthy across that multi-`.claude/` layout.

| Script | Purpose |
|---|---|
| [`generate-inventory.sh`](generate-inventory.sh) | Regenerates `.claude/docs/agent-roster.md` and `.claude/docs/skill-inventory.md` from frontmatter on disk. Group-by-scope, with subdirectory `.claude/` trees called out separately. |
| [`doc-maintenance.sh`](doc-maintenance.sh) | Validates `.claude/` doc health: backtick path references resolve, skill depth conforms to the loader constraint, inventory files match disk reality (and are byte-identical to regenerated output), hook scripts in `settings.json` exist, `@`-includes resolve. |

## generate-inventory.sh

```bash
.claude/scripts/generate-inventory.sh                 # write outputs
.claude/scripts/generate-inventory.sh --dry-run       # print to stdout instead of writing
ROSTER_OUT=/tmp/r INVENTORY_OUT=/tmp/i \
  .claude/scripts/generate-inventory.sh               # override output paths
```

What it scans:

- `.claude/agents/*.md` — extracts `name`, `description`, `model`, `maxTurns`, `effort` from frontmatter
- `.claude/skills/*/SKILL.md` — extracts `name`, `description`, `topic`, `user-invocable`
- All other `*/.claude/agents/` and `*/.claude/skills/` directories under the repo root (multi-`.claude/` repos)

Outputs:

- `.claude/docs/agent-roster.md` — table of all agents grouped by scope
- `.claude/docs/skill-inventory.md` — table of all skills grouped by scope and topic

The `PREDEFINED_TOPICS` list at the top of the script controls topic ordering — edit it to match your project's skill taxonomy.

## doc-maintenance.sh

```bash
.claude/scripts/doc-maintenance.sh
```

Three sections of checks:

1. **Path validation** — every backtick-quoted `.claude/...` path in any `.claude/*.md` file must resolve to a real file. Catches stale references after a rename or move.
1. **Skill depth** — Claude Code's loader only discovers skills at `{skills_root}/{name}/SKILL.md`. Any `SKILL.md` at depth ≥3 is invisible. The check reports them.
1. **Inventory sync** — every agent on disk must appear in `agent-roster.md`; every skill must appear in `skill-inventory.md`. Then re-runs `generate-inventory.sh` to a temp dir and `diff`s — content equality, not just presence.
1. **Cross-references** — every hook command in `settings.json` resolves to an existing script (with `$CLAUDE_PROJECT_DIR` and `$HOME` substitution); every `@`-include in `CLAUDE.md` resolves; every backtick-quoted `*.md` path in skill files resolves.

Exit codes:

| Exit | Meaning |
|---|---|
| 0 | All clean |
| 1 | Issues found (non-blocking — useful for CI as a warning) |
| 2 | Script error |

## CI usage

Both scripts are designed to run in CI:

```yaml
# .github/workflows/claude-config-validate.yaml
on:
  pull_request:
    paths:
      - '.claude/**'

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@<sha>
      - run: .claude/scripts/doc-maintenance.sh
```

Pair with a CI step that fails if `generate-inventory.sh --dry-run` produces output that differs from the committed `agent-roster.md` / `skill-inventory.md` — that catches the case where someone added a new agent or skill but forgot to regenerate the inventory.

## Why this lives in `_scripts/inventory/`

These are CI / maintenance scripts that operate on `.claude/` content but aren't themselves hooks or skills. They live in a separate `inventory/` subdirectory under `examples/scripts/` so the `_lib/` convention (utilities sourced by hooks) stays distinct from "things you run as standalone commands."
