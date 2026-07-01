---
name: delete-failed-runs
description: List and delete failed/cancelled workflow runs. Usage - /delete-failed-runs [workflow-name]
user-invocable: true
allowed-tools: Bash(gh *), AskUserQuestion
argument-hint: "[workflow-name]"
---

# Delete Failed Runs

List and delete failed or cancelled GitHub Actions workflow runs.

## Steps

### 1. Determine scope

If `$ARGUMENTS` is provided, use it as the workflow name filter. Otherwise, list all failed/cancelled runs.

Optional filters (parse from arguments):

- Workflow name: e.g., `deploy.yaml`, `container.yaml`
- `--branch <name>` or `--pr <number>`: filter by branch or PR
- `--cancelled`: include cancelled runs (default: include both failed and cancelled)

### 2. List runs

```bash
gh run list --repo <org>/<repo> \
  --status failure \
  --limit 20 \
  --json databaseId,workflowName,headBranch,createdAt,conclusion,event \
  --jq '.[] | "\(.databaseId)\t\(.workflowName)\t\(.headBranch)\t\(.createdAt)\t\(.conclusion)"'
```

If including cancelled:

```bash
gh run list --repo <org>/<repo> \
  --status cancelled \
  --limit 20 \
  --json databaseId,workflowName,headBranch,createdAt,conclusion,event \
  --jq '.[] | "\(.databaseId)\t\(.workflowName)\t\(.headBranch)\t\(.createdAt)\t\(.conclusion)"'
```

If a workflow filter is specified, add `--workflow {name}`.
If a branch filter is specified, add `--branch {name}`.

### 3. Present the list

Show a numbered table:

```text
#  Run ID       Workflow            Branch                 Date        Status
1  12345678901  deploy.yaml         TICKET-123-feature     2026-03-02  failure
2  12345678902  container.yaml      TICKET-123-feature     2026-03-02  cancelled
```

### 4. Confirm deletion

Ask: "Delete all N runs listed above? Or specify numbers to delete selectively (e.g., 1,3,5)."

### 5. Delete

```bash
gh run delete {run_id} --repo <org>/<repo>
```

Report results: "Deleted N runs."

## Safety

- Always show the list and get confirmation before deleting
- Never delete runs with status `success` or `in_progress`
