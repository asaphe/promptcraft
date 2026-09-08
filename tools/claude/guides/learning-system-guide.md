# Learning System Guide

How to build a Claude Code setup that captures operational knowledge from its own mistakes, judges which of it is worth keeping, and routes the survivors to the right file.

## The implementation ships as a plugin

The three-hook system this guide used to document — `SessionStart` injects, `SessionEnd` and `PreCompact` regex-scan the transcript, everything lands in a `pending-learnings.md` staging file — is no longer maintained here. It ships, rebuilt, as
**[claude-learning-loop](https://github.com/asaphe/claude-learning-loop)**:

```text
/plugin marketplace add asaphe/claude-learning-loop
/plugin install learning-loop@claude-learning-loop
```

What changed is where the judgment lives. Regex over a transcript is a decent *trigger* and a poor *filter*: it over-captures (any message starting with "no") and it cannot see the failure that matters most — a silent wrong guess the user quietly worked around, which produces no correction phrase at all. The plugin keeps a thin passive layer (a `Stop` hook that suggests capture, a `PreCompact` reminder) and moves the deciding into three skills:

| Skill | Phase | What it does |
|---|---|---|
| `/learning-loop:wrap-up` | Capture | Model-curated scan of the conversation for friction the regex misses |
| `/learning-loop:eval` | Quality gate | Scores each candidate on destination fit, recurrence, coverage, severity |
| `/learning-loop:learn` | Codify | Writes surviving candidates as principles, per a destinations manifest |

The rest of this guide is the design reasoning behind that system — the part that outlives any particular implementation, and what you need if you are building your own.

## What to detect

Two signal classes, evaluated against the transcript, plus one that has nothing to do with what the user said:

| Signal | Mechanism | Trigger |
|---|---|---|
| **Correction patterns** | Regex over user-typed text: pushback phrasing ("stop doing", "not that", "I said", "why did you", "you assumed") | 2+ matches per session |
| **Explicit codify requests** | Regex over user-typed text: "remember this", "codify this", "new rule", "keep happening", "every session" | 1 match — the user asked |
| **Tool failure rate** | Count `tool_result` blocks with `is_error: true` against the total | Both thresholds: 6+ failures AND ≥25% failure rate |

Two details make the regexes usable at all:

- **Scan only human-typed text.** User-role messages in the transcript mix text blocks with tool results. Keep `type == "text"` blocks only — otherwise correction phrases inside tool output (error messages, file contents, quoted logs) fire the detector against the assistant's own evidence.
- **Split correction phrasing from codify phrasing.** They warrant different thresholds: pushback needs repetition to be signal (a single "no, not that" is routine), while "codify this" is signal on the first occurrence.

The tool-failure signal exists because corrections only catch what the user noticed *and* verbalized. A session where a third of the tool calls failed is friction worth examining even if the user silently absorbed every failure.

### Thresholds

| Variable | Default | Meaning |
|---|---|---|
| `LEARN_CORRECTION_MIN` | 2 | Correction-pattern matches needed to flag a session |
| `LEARN_TOOL_FAIL_MIN` | 6 | Absolute floor of failed tool calls |
| `LEARN_TOOL_FAIL_RATE` | 25 | Minimum failure percentage |

The failure gate is deliberately dual. The absolute floor filters short sessions — 2 failures out of 5 calls is normal exploration, not a pattern. The rate filters long ones — 8 failures out of 300 calls is statistically unremarkable. Both must pass.

### Per-session and batch are not redundant

Per-session detection evaluates the session that just ended. A batch scanner walks every project's transcripts from the last N days and applies identical thresholds. You want both, because batch covers what per-session structurally cannot:

1. **Sessions that never fired the hook.** Crashed sessions, killed terminals, machines where the hook was not registered. The transcripts still exist; batch mining recovers them.
2. **Cross-session recurrence.** One flagged session is weak evidence. The same correction surfacing across several sessions and projects in a week is a strong rule candidate, and only a consolidated view exposes it.
3. **Retroactive tuning.** Tightening a regex in the per-session hook only affects future sessions. A batch run re-applies current detection logic to existing history immediately.

Have both consumers source one detection library so the logic cannot drift between them.

## Where a learning goes

Detection is the cheap half. The expensive half is deciding whether a candidate is a durable principle or a one-off, and which file owns it:

| Signal | Classification | Target |
|---|---|---|
| Applies to any developer in the repo | **Team-wide** | `.claude/rules/{subdirectory}/{rule}.md` |
| Specific to one agent's domain | **Agent-specific** | `.claude/agents/{agent}.md` |
| User workflow preference | **Personal global** | `~/.claude/CLAUDE.md` |
| User preference for this project | **Personal project** | `CLAUDE.local.md` |
| Temporary or unverified | **Not yet a rule** | Leave it as a note; promote once it recurs |

Configure this routing per-user rather than hardcoding it in a hook — the plugin does it with a destinations manifest, so the same detector serves someone whose rules live in a monorepo and someone whose live in a dotfiles repo.

## Rules organization

As rules accumulate, a flat `.claude/rules/` directory creates token pressure — every rule loads into every session regardless of relevance. Organize into subdirectories with conditional loading.

```text
.claude/rules/
+-- general/              # Always loaded (no paths: filter)
|   +-- operational-safety.md
|   +-- pr-review.md
+-- devops/               # Loaded only when working on devops/ or .github/ files
|   +-- ci-runners.md
|   +-- terraform-apply.md
```

### `paths:` frontmatter

Add a YAML frontmatter block to conditionally load a rule:

```markdown
---
paths: ["devops/terraform/**", "devops/helm-reusable-chart/**"]
---
# Terraform Apply Safety Rules
- **Rule** -- Description.
```

Claude Code only loads this rule when the session involves files matching those globs. Without `paths:`, the rule loads unconditionally.

- **`general/`** is for cross-cutting rules (safety, review standards) — no `paths:` filter, always loaded.
- **Domain subdirectories** (`devops/`, `backend/`, `frontend/`) use `paths:` to scope loading.
- **Agents are not affected** — agents reference rules explicitly by path with the Read tool, bypassing auto-loading entirely.

One caveat that bites: `paths:` fires on Read-tool access to matching files. A rule whose content must be in context *before* the model touches a matching file — anything a hook depends on, or any always-on discipline — cannot use it.

## Rule retirement

Rules accumulate. Without maintenance they bloat the context window and go stale.

- Rules **never triggered** in the last 30 days are retirement candidates.
- Rules **violated frequently** need strengthening or better placement, not repetition.
- Rules referencing **deprecated tools or patterns** should be updated or removed.

A review-date comment (`<!-- Last reviewed: YYYY-MM-DD -->`) helps humans track staleness; Claude ignores HTML comments in context, so it costs the model nothing.

### Cross-clone audit

If you keep multiple checkouts of one repo (see [Auto Memory Guide — Multi-Clone Strategy](auto-memory-guide.md#multi-clone-memory-strategy)), learnings fragment across clone-specific directories. Periodically: discover every per-clone notes directory, read all of them rather than just the index files, and classify each entry as **promote** (move to `~/.claude/CLAUDE.md` or `.claude/rules/`), **already covered** (delete), or **stale** (delete). The same correction appearing in three or more clones is strong evidence of a real gap.

## Plugin distribution

For teams with multiple repositories, package the system as a Claude Code plugin rather than copying hooks into each repo:

```text
team-learning/
+-- .claude-plugin/
|   +-- plugin.json
+-- skills/
|   +-- <skill-name>/
|       +-- SKILL.md
+-- agents/
|   +-- <agent-name>.md
+-- hooks/
    +-- hooks.json
    +-- <hook>.sh
```

Reference hook scripts from `hooks.json` via `${CLAUDE_PLUGIN_ROOT}` so the plugin is relocatable, and keep exactly one copy of each script — a plugin that ships a second copy of a hook you also maintain elsewhere is how a fix gets applied in one place and not the other.

**Do not install the plugin in a project whose `settings.json` already registers the same hooks.** They fire twice, in no guaranteed order. Pick one.

## Complementary tools

| Tool | Purpose | Relationship |
|---|---|---|
| **[claude-learning-loop](https://github.com/asaphe/claude-learning-loop)** | Capture, gate, codify | The maintained implementation of this guide |
| **`.claude/rules/`** | Team-shared operational rules | Final destination for team-wide learnings |
| **[RTK](https://github.com/rtk-ai/rtk) `learn`** | CLI correction mining | Failed→retried command pairs, a different signal source |

RTK's `learn` subcommand scans session history for commands that failed and were retried differently, then extracts reusable rules:

```bash
rtk learn                    # Scan current project, last 30 days
rtk learn --all --since 60   # Scan all projects, last 60 days
rtk learn --write-rules      # Generate .claude/rules/cli-corrections.md
```

Caveats worth respecting:

- **Review before committing.** `--write-rules` outputs raw command pairs, which may carry infrastructure IDs, account details, and internal repo names. Always read the generated file first, especially in a public repo.
- **Signal-to-noise depends on the workflow.** It works best where command patterns recur (build/test/lint cycles). For ad-hoc infrastructure work most corrections are one-off; `--min-occurrences 2` surfaces only the recurring ones.
- **Run it as a report first.** Confirm the corrections are genuinely reusable before generating the rules file.

The division of responsibility: a transcript-based system captures *behavioral* corrections ("verify before asserting"); `rtk learn` captures *CLI* corrections ("pass `--ref branch` to `gh workflow run`"). Both end up in `.claude/rules/`, from different signal sources.

## Key principles

1. **Automate detection, not classification.** Hooks and regexes detect signals; a model or a human approves and routes. Fully automated rule creation manufactures noise faster than you can read it.
2. **Detection is a trigger, not a verdict.** Anything that survives to a rule file should have cleared a judgment step that a regex cannot perform.
3. **Personal vs shared is a spectrum.** When in doubt, keep it personal and promote once the pattern recurs.
4. **Rules carry no provenance.** No dates, confirmation counts, or session references — the rule either stands on its own as guidance or it does not. Metadata is context tokens spent on archaeology.
5. **Capture the general principle, not the instance.** If a rule says "don't use X" but the real principle is "only A, B and C support feature Y", teach the principle. Narrow rules get bypassed by the next variant.
6. **Zero UX impact.** Anything scanning a transcript runs async. A synchronous hook whose output becomes context must be a file-existence check, not a scan.
7. **Pipefail safety is non-negotiable.** Every `jq` and `grep` pipeline in a hook must end with `|| true`. Under `set -eo pipefail`, a malformed transcript or a no-match `grep` aborts the script silently — lost learnings, no error.
8. **One copy of each script.** Duplicate-maintenance is how a fix lands in one place and not the other.
9. **Scope rules with `paths:`.** Token usage should stay proportional to task relevance as the rule set grows.
