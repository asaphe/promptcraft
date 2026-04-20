---
name: deploy
description: >-
  Trigger a deployment workflow via GitHub Actions. Interactively selects
  environment, application, and deployment target. Usage - /deploy [application]
user-invocable: true
allowed-tools: Bash(gh *), Bash(aws *), AskUserQuestion, Read, Grep, Glob
argument-hint: "[application-name]"
---

# Deploy Application

Trigger a deployment workflow via `gh workflow run`.

## Steps

### 1. Determine parameters

If `$ARGUMENTS` is provided, use it as the application name. Otherwise, ask the user to select.

**Valid applications:**
<api-server>, <web-app>, <worker-service>, <data-pipeline>, <event-processor>

Ask the user (if not already specified):

1. **Environment**: staging or production
2. **Deployment target**: Select from available targets for the environment
3. **Image tag** (REQUIRED resolution — see step 1b below)
4. **Plan only?**: Whether to run terraform plan without applying (default: no)

### 1b. Resolve image tag from registry (MANDATORY)

Do NOT silently default to "latest from main". Always resolve available tags:

```bash
aws ecr describe-images \
  --repository-name {application} \
  --query 'sort_by(imageDetails,&imagePushedAt)[-3:].{tags:imageTags,pushed:imagePushedAt}' \
  --output table \
  --profile <env> \
  --region <region>
```

Present the 3 most recent tags to the user and ask them to select one.

### 2. Resolve the workflow file

- Production -> `prod_deployments.yaml`
- Staging -> `stg_deployments.yaml`

### 3. Confirm with user

Before triggering, show a summary:

```text
Deploying:
  Application:  {application}
  Environment:  {environment}
  Target:       {deployment_target}
  Image Tag:    {image_tag}
  Plan Only:    {yes/no}
  Workflow:     {workflow_file}
```

Ask for explicit confirmation before proceeding.

### 4. Trigger the workflow

```bash
gh workflow run {workflow_file} \
  --repo <org>/<repo> \
  --ref main \
  -f application={application} \
  -f deployment_name={deployment_target} \
  -f terraform_plan={true|false} \
  -f image_tag={tag}
```

### 5. Monitor

After triggering:

```bash
sleep 5
gh run list --repo <org>/<repo> --workflow={workflow_file} --limit 1 --json databaseId,status,url --jq '.[0]'
```

Share the run URL with the user. Offer to watch for completion.

## Safety

- NEVER deploy without explicit user confirmation
- NEVER default to production — always ask
- If the user says "deploy to prod" without specifying a target, ask which one
- NEVER silently default to "latest from main" — always resolve from registry first
