---
name: graduate-learnings
description: >-
  Process pending learning candidates — classify, propose rules, and graduate
  to the correct target (.claude/rules/, agents, or personal config).
  Usage - /graduate-learnings
user-invocable: true
allowed-tools: Agent, Read, Write, Edit, Glob, Grep, Bash(git *), Bash(find *), AskUserQuestion
---

# Graduate Pending Learnings

Process accumulated learning candidates from `pending-learnings.md` and graduate them to permanent rules.

> **Prerequisites:** this skill is the consumer end of a learning-capture pipeline. It expects something else (typically the `learning-capture` hook family — `session-start-learnings`, `session-end-learnings`, `precompact-preserve`) to write candidate entries to `pending-learnings.md` based on correction signals during sessions. Without those hooks installed, this skill has no input. Build (or install) the producer side first.

## Steps

### 1. Find and read pending learnings

Locate the pending-learnings file for the current project. Scope to the project matching the current working directory:

```bash
find ~/.claude/projects/ -path "*$(basename "$PWD")*/memory/pending-learnings.md" -size +0c 2>/dev/null
```

If no match, broaden to all projects but prefer the one matching the cwd. Read each non-empty file found. If no pending learnings exist, inform the user and stop.

### 2. Parse candidates

Each candidate section starts with `## Session` or `## Pre-compaction`. Extract:

- The correction signals (user quotes)
- The retry patterns
- The session context (working directory, tool call count)

### 3. Classify each candidate

For each candidate, determine the target. Use the `learning-classifier` agent if ambiguous:

| Signal | Target | Path |
|--------|--------|------|
| Applies to any developer in this repo | `.claude/rules/{subdirectory}/{rule}.md` | Committed (git) |
| Specific to one agent's behavior | `.claude/agents/{agent}.md` | Committed (git) |
| User workflow preference | `~/.claude/CLAUDE.md` or `~/.claude/docs/` | Personal |
| Too narrow / one-time incident | Drop | — |

### 4. Present proposals

For each candidate, present to the user:

```text
## Candidate 1/N (from session DATE)

Signal: "user correction quote"

Proposed rule: **Rule title** — What to do and why.
Target: .claude/rules/general/operational-discipline.md
Classification: team-wide

[Accept] [Edit] [Skip] [Drop]
```

Use `AskUserQuestion` for each candidate. Do not batch — the user needs to evaluate each individually.

### 5. Apply accepted rules

For accepted candidates:

- Read the target file
- Append the new rule in the correct section
- If the target file doesn't exist, create it with proper structure

For edited candidates, apply the user's modifications.

### 6. Clean up

After all candidates are processed (accepted, edited, or dropped):

- Clear the `pending-learnings.md` file
- Report: N accepted, N edited, N skipped, N dropped

## Important

- Check for duplicate rules before proposing — grep existing rules for similar content
- Ask "would this prevent the next variant?" — if too narrow, extract the general principle
- Never auto-graduate without user approval
