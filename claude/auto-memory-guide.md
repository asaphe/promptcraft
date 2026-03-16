# Claude Code Auto Memory Guide

How to design effective persistent memory entries that improve Claude Code's performance across sessions.

## What Auto Memory Is

Claude Code provides a persistent, file-based memory system at `~/.claude/projects/<project>/memory/`. Each conversation loads a `MEMORY.md` index file from this directory, giving Claude access to information saved from previous sessions.

Memory entries are markdown files with YAML frontmatter. The `MEMORY.md` file serves as an index — it contains only links to memory files with brief descriptions, not the memories themselves.

## Memory Types

Effective memory systems categorize entries by purpose. Four types cover most use cases:

### User Memories

Information about the user's role, goals, and expertise level. These help tailor responses — you collaborate differently with a senior infrastructure engineer than with someone writing their first Terraform module.

**When to save:** When you learn details about the user's role, domain expertise, or knowledge gaps.

**Examples:**

- User is a data scientist, currently focused on observability/logging
- Deep Go expertise, new to React — frame frontend explanations using backend analogues

### Feedback Memories

Corrections and behavioral guidance from the user. These are the highest-value memory type — they prevent repeating the same mistakes across sessions.

**When to save:** Any time the user corrects your approach in a way that could apply to future sessions. These often take the form of "no, not that — instead do..." or "don't...".

**Structure:** Lead with the rule, then a **Why:** line (the reason) and a **How to apply:** line (when this guidance kicks in). The *why* helps judge edge cases instead of blindly following the rule.

**Examples:**

- Don't mock the database in integration tests. **Why:** Prior incident where mock/prod divergence masked a broken migration. **How to apply:** When writing tests that touch data stores, use real connections.
- Stop summarizing what you just did at the end of every response. **Why:** User can read the diff. **How to apply:** Skip trailing summaries unless the user asks "what did you change?"

### Project Memories

Information about ongoing work, goals, and decisions that isn't derivable from code or git history.

**When to save:** When you learn who is doing what, why, or by when. Always convert relative dates to absolute dates (e.g., "Thursday" to "2026-03-05") so the memory remains interpretable later.

**Structure:** Lead with the fact or decision, then **Why:** and **How to apply:** lines.

**Examples:**

- Merge freeze begins 2026-03-05 for mobile release cut. **Why:** Mobile team cutting a release branch. **How to apply:** Flag non-critical PR work scheduled after that date.
- Auth middleware rewrite is driven by legal/compliance requirements around session token storage. **Why:** Legal flagged current approach. **How to apply:** Scope decisions should favor compliance over ergonomics.

### Reference Memories

Pointers to where information lives in external systems. These help you know where to look without storing the information itself (which goes stale).

**When to save:** When you learn about resources in external systems and their purpose.

**Examples:**

- Pipeline bugs tracked in Linear project "INGEST"
- `grafana.internal/d/api-latency` is the oncall latency dashboard — check when editing request-path code

## Memory File Format

Each memory is a standalone markdown file with YAML frontmatter:

```markdown
---
name: descriptive-name
description: one-line description used to decide relevance in future conversations
type: user | feedback | project | reference
---

Memory content here. For feedback and project types, structure as:
rule/fact, then **Why:** and **How to apply:** lines.
```

The `description` field is critical — it determines whether the memory gets loaded in future conversations. Be specific enough that relevance can be assessed from the description alone.

## MEMORY.md Index

`MEMORY.md` is an index file, not a memory. It contains only links to memory files with brief descriptions:

```markdown
- [user_role.md](user_role.md) — User is a platform engineer focused on K8s migration
- [feedback_testing.md](feedback_testing.md) — Use real databases in integration tests, not mocks
- [project_auth_rewrite.md](project_auth_rewrite.md) — Auth rewrite driven by compliance, not tech debt
```

Keep the index concise — lines after ~200 are truncated during loading. Organize semantically by topic, not chronologically.

## What NOT to Save

Memory should contain information that can't be derived from the project itself:

| Don't Save | Why | Better Source |
|-----------|-----|---------------|
| Code patterns, architecture, file paths | Derivable from current code | Read the files |
| Git history, recent changes | `git log` / `git blame` are authoritative | Run the command |
| Debugging solutions | The fix is in the code; commit message has context | Read the diff |
| Content already in CLAUDE.md | Loaded every session already | Reference CLAUDE.md |
| Ephemeral task details | Only useful in current conversation | Use tasks or plan mode |

## Design Principles

### Prefer specificity over breadth

A memory that says "user prefers concise responses" is less useful than "user wants no trailing summaries after code changes — they read the diff directly." The specific version tells you exactly when and how to apply it.

### Update, don't accumulate

Before creating a new memory, check if an existing one covers the same topic. Update it rather than creating a duplicate. Remove memories that turn out to be wrong or outdated.

### Feedback memories are the highest ROI

Most productivity gains come from not repeating mistakes. Prioritize saving corrections and behavioral guidance over general facts. A single feedback memory like "don't use `terraform import` for resources managed by another module" prevents an hour of debugging.

### Keep the index current

Orphaned index entries (pointing to deleted files) and stale memories waste context tokens. Periodically review and prune.

## When to Access Memories

- When specific known memories seem relevant to the current task
- When the user references work from a prior conversation
- When the user explicitly asks you to recall or remember something

Don't load all memories at session start — only access what's relevant to the task at hand.

## Memory vs Other Persistence

| Mechanism | Scope | Use For |
|-----------|-------|---------|
| **Auto memory** | Cross-session, per-project | User preferences, corrections, project context |
| **Plan mode** | Current session | Implementation approach alignment |
| **Tasks** | Current session | Progress tracking within a session |
| **CLAUDE.md** | Every session, all users | Team-wide rules and standards |
| **Dev docs** (markdown files) | Cross-session | Detailed handoff between sessions |

## Related Resources

- [Global CLAUDE.md Guide](global-claude-md-guide.md) — What belongs in CLAUDE.md vs memory
- [Learning System Guide](learning-system-guide.md) — Automated correction capture (complements memory)
- [Best Practices](claude-best-practices.md) — Context management strategies
