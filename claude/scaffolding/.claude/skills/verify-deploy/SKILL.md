---
name: verify-deploy
description: >-
  Post-deployment health check. Verifies pod status, logs, events, Helm release,
  and ingress for a deployed application. Usage - /verify-deploy [application] [target]
user-invocable: true
allowed-tools: Bash(kubectl *), Bash(helm *), Bash(aws *), AskUserQuestion, Read, Grep, Glob
argument-hint: "[application] [deployment-target]"
---

# Verify Deployment

Post-deployment health check that presents a GREEN/YELLOW/RED summary.

## Steps

### 1. Determine parameters

If `$ARGUMENTS` is provided, parse application and deployment target from it. Otherwise, ask:

1. **Application**: Which service to check
2. **Deployment target**: Which namespace/deployment to check

### 2. Run health checks

Execute all checks and collect results:

#### 2a. Pod Status

```bash
kubectl get pods -n {target} -l app={application} -o wide
```

- GREEN: All pods Running and Ready (READY column shows x/x)
- YELLOW: Pods Running but not all Ready, or recent restarts
- RED: CrashLoopBackOff, Error, Pending, ImagePullBackOff, or no pods found

#### 2b. Recent Logs

```bash
kubectl logs -n {target} -l app={application} --tail=30 --since=5m
```

- GREEN: No ERROR/FATAL/CRITICAL lines
- YELLOW: WARNING lines present
- RED: ERROR/FATAL/CRITICAL lines present

#### 2c. Warning Events

```bash
kubectl get events -n {target} --sort-by='.lastTimestamp' --field-selector type=Warning | tail -10
```

- GREEN: No warning events in last 10 minutes
- YELLOW: Warning events exist but unrelated to the target app
- RED: Warning events related to the target app

#### 2d. Helm Release

```bash
helm list -n {target} --filter {application} -o json
```

- GREEN: Status "deployed", revision matches expected
- RED: Status "failed", "pending-install", or not found

### 3. Present summary

```text
Deployment Health: {application} in {target}
================================================

  Pods:      GREEN  -- 3/3 Running, 0 restarts
  Logs:      YELLOW -- 2 WARNING lines (connection retry)
  Events:    GREEN  -- No warning events
  Helm:      GREEN  -- v1.2.3, revision 42, deployed

Overall: HEALTHY (1 advisory)

Advisories:
  - [YELLOW] Logs show connection retry warnings — may be transient
```

### 4. Offer next steps

- If RED: Offer to dig deeper into the failing component
- If YELLOW: Note the advisory items, offer to investigate
- If GREEN: Confirm deployment looks healthy

## Safety

- Read-only skill — no state changes
- All commands are observational (get, list, logs, describe)
- If kubectl context is wrong, warn and ask to switch
