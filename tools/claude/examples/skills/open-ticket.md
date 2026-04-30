---
name: open-ticket
description: Create a project management ticket in the current sprint, assign to the current user, set team/points, and create a git branch. ONLY when user explicitly asks to open or create a ticket. Usage - /open-ticket [title]
user-invocable: true
allowed-tools: Bash(git *), Read, Glob, Grep, AskUserQuestion, mcp__project-mgmt__create_sprint_task, mcp__project-mgmt__get_current_sprint, mcp__project-mgmt__get_current_user, mcp__project-mgmt__list_teams
argument-hint: "[task-title]"
---

# Open Ticket

Create a ticket in the current sprint and open a git branch for it.
This is the most common workflow — optimize for speed with smart defaults.

**Prerequisite:** This skill assumes you have an MCP server registered for your project / issue tracker (named `mcp__project-mgmt__*` in this example, but adapt the tool calls below to your tracker's MCP — ClickUp, Linear, Jira, GitHub Issues, etc.). The MCP must expose tools for creating a sprint task, getting the current sprint, getting the current user, and listing teams.

## Safety: Duplicate Prevention

Before creating anything, check for existing ticket/branch context:

1. **Check conversation context** — If a `PROJ-XXXX` ticket number or a `dev-XXXX-*` branch has already been mentioned or created in this session, STOP and ask: "There's already a ticket (PROJ-XXXX) in this session. Create a new one anyway?"
2. **Check current branch** — Run `git branch --show-current`. If already on a `dev-*` branch (not `main`), STOP and ask: "You're already on branch `{branch}`. Create a new ticket and branch anyway?"
3. **This skill is explicit-request-only** — Never trigger proactively. Only run when the user explicitly asks to create a ticket, open a ticket, or start a task.

## Steps

### 1. Gather parameters

If `$ARGUMENTS` is provided, use it as the task title. Otherwise, ask the user.

**Infer team automatically** using this priority:

1. Title keywords: `ci`, `terraform`, `deploy`, `helm`, `docker`, `k8s`, `pipeline` -> **devops**; `mesh`, `workflow`, `agent`, `temporal` -> **ai-agents**; `webapp`, `ui`, `frontend`, `api` -> **application**; `dbt`, `dagster`, `clickhouse`, `pipeline`, `ingestion` -> **data**; `auth`, `okta`, `sso`, `rbac` -> **security**
2. Recent file context: if the conversation has been working in `devops/` -> **devops**; `python/<workflow-service>/` -> **ai-agents**; `typescript/` -> **application**; `python/<data-service>/` -> **data**
3. If still ambiguous, ask with the inferred guess as default

**Defaults** (confirm in one shot, don't ask one by one):

- **Points**: 1 (unless user specifies)
- **Assign to me**: yes (always, via `assign_to_me=True`)
- **Description**: empty (unless context provides one)

Present the plan for confirmation in a single block:

```text
Creating ticket:
  Title:  {title}
  Team:   {team} (inferred from {reason})
  Points: {points}
  Sprint: {sprint_name}
  Assign: you

Proceed? (y to confirm, or adjust)
```

### 2. Create the ticket

Call `create_sprint_task` from the project management MCP:

```text
create_sprint_task(
    name="{title}",
    team="{team}",
    points={points},
    description="{description}",
    assign_to_me=True,
)
```

This single call handles: sprint detection, user resolution, team label, assignment, and points.

### 3. Create the git branch

From the response, extract the custom ID number (e.g., `PROJ-12811` -> `12811`).

Branch name format: `dev-{number}-{kebab-case-short-description}`

- Max 6-8 words in the description
- Branch from `main`

```bash
git checkout -b dev-{number}-{short-description} main
```

### 4. Summary

Always display a clear summary:

```text
Ticket:  PROJ-{number} — {title}
URL:     {url}
Sprint:  {sprint_name}
Team:    {team}
Points:  {points}
Branch:  dev-{number}-{short-description}
```

## Reference

Document your tracker MCP's workspace IDs, sprint conventions, and user-resolution patterns alongside the MCP itself (e.g., a README in the MCP server's repo). This skill calls the MCP — it doesn't replicate the MCP's setup instructions.
