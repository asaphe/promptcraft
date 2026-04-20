---
name: checkpoint
description: >-
  Capture a session state snapshot for context handoff between sessions. Records
  branch, changes, recent commits, and current work summary. Usage - /checkpoint
user-invocable: true
allowed-tools: Bash(git *), Read, Grep, Glob, AskUserQuestion
argument-hint: ""
---

# Session Checkpoint

Capture a snapshot of the current session state for handoff to a future session.

## Steps

### 1. Gather state

```bash
git branch --show-current
git status --short
git log --oneline -10
git diff --stat HEAD
pwd
```

### 2. Summarize current work

Based on the conversation so far, create a summary of:

- **What was the goal** — What was the user trying to accomplish?
- **What was done** — Key actions taken, files modified
- **What remains** — Outstanding tasks, next steps, open questions
- **Key decisions made** — Any choices or trade-offs discussed
- **Gotchas discovered** — Anything that caused problems or was unexpected

### 3. Format as structured markdown

```markdown
## Session Checkpoint — {date} {time}

**Branch:** {branch}
**Working directory:** {path}

### Goal
{1-2 sentence description}

### Completed
- {action 1}
- {action 2}

### Remaining
- [ ] {task 1}
- [ ] {task 2}

### Uncommitted Changes
{git status output or "Clean working tree"}

### Recent Commits
{last 5 commits on this branch}

### Key Decisions
- {decision 1}: {rationale}

### Gotchas
- {issue 1}: {what happened and resolution}

### Resume Instructions
To continue this work in a new session:
1. `cd {working_directory}`
2. `git checkout {branch}`
3. {next step to take}
```

### 4. Offer to save

Ask the user if they want to:

- **Copy to clipboard** — Just display for manual copy
- **Capture rules** — Add any gotchas as operational rules

## Safety

- Read-only — only runs git commands and reads files
- Does not commit, push, or modify any files unless the user asks to save rules
