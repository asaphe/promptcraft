# Skill Template

Ready-to-copy template for creating a new Claude Code skill. Copy to `.claude/skills/<skill-name>/SKILL.md` and customize.

## Template

````markdown
---
name: my-skill
description: >-
  Brief description of what this skill does.
  Usage - /my-skill [arguments]
user-invocable: true
allowed-tools: Bash(command *), Read, Grep, Glob, AskUserQuestion
argument-hint: "[target] [options]"
---

# Skill Title

Brief one-line description of what this skill accomplishes.

## Steps

### 1. Determine parameters

If `$ARGUMENTS` is provided, parse the target and options from it. Otherwise, ask the user.

**Valid targets:**
target-a, target-b, target-c

Ask the user (if not already specified):

1. **Target**: Which resource to operate on
2. **Environment**: staging or production
3. **Options**: Any additional configuration

### 2. Validate preconditions

Before executing, verify:

```bash
# Check current context/state
command-to-verify-state
```

If preconditions are not met, explain what's wrong and how to fix it.

### 3. Execute operation

```bash
# Run the operation
command-to-execute --target {target} --env {environment}
```

### 4. Present results

Format results:

```
Operation Results: {target} in {environment}
================================================

  Status:    SUCCESS
  Duration:  {time}
  Output:    {summary}

Details:
  - {detail 1}
  - {detail 2}
```

### 5. Offer next steps

Based on results:
- If success: suggest follow-up actions
- If partial: offer to investigate failures
- If failure: present diagnostic information

## Safety

- Describe what this skill will NOT do
- List any confirmation requirements
- State whether this is read-only or modifies state
- Note any environment restrictions
````

## Customization Checklist

When adapting this template:

- [ ] Replace `my-skill` with your skill name (kebab-case)
- [ ] Write a clear one-line description
- [ ] Set `allowed-tools` to the minimum needed (see tool selection guide below)
- [ ] Set `argument-hint` to show expected parameters
- [ ] Fill in the valid targets list
- [ ] Define the actual commands in steps 2-3
- [ ] Design the output format for step 4
- [ ] Write explicit safety boundaries
- [ ] Add a confirmation gate before any destructive step

## Tool Selection Guide

| Skill Purpose | Recommended Tools |
| ------------- | ----------------- |
| Read-only inspection | `Bash(kubectl *), Bash(aws *), Read, Grep, Glob, AskUserQuestion` |
| Git/GitHub operations | `Bash(git *), Bash(gh *), Read, Grep, Glob, AskUserQuestion` |
| Deployment triggers | `Bash(gh *), AskUserQuestion, Read, Grep, Glob` |
| File scaffolding | `Bash(*), Read, Write, Edit, Glob, Grep, AskUserQuestion` |
| Terraform operations | `Bash(terraform *), Bash(aws *), Read, Write, Edit, Glob, Grep, AskUserQuestion` |
| History/analysis | `Bash(cat *), Bash(jq *), Read, Grep, Glob, AskUserQuestion` |
| Pure investigation | `Read, Grep, Glob, AskUserQuestion` |

**Principle:** Grant the minimum tools needed. A read-only skill should never have `Write` or `Edit`. A skill that only uses `gh` should not have `Bash(*)`.
