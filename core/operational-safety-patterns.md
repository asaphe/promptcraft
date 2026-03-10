# Operational Safety Patterns

Generalized safety patterns for AI-assisted coding sessions, distilled from real-world incidents. These patterns apply regardless of tech stack or project type.

## Session Continuity

### Re-Verify State After Context Continuation

After any context continuation, session handoff, or conversation compaction, **re-read actual state** from the filesystem. Never rely on summaries from the previous context.

What to re-verify:

- Current git branch (`git branch --show-current`)
- Current working directory
- Active workspace or environment context
- Any mutable state the session was tracking (image tags, resource names, file contents)

**Why this matters:** Context summaries can lose precision. A branch name, workspace, or tag from the summary may be stale or subtly wrong. The cost of a quick re-read is negligible; the cost of operating on wrong state can be catastrophic.

### Checkpoint Deep Sessions Proactively

When a session is deep (50+ tool calls, multiple modules or subsystems), proactively offer a checkpoint summary:

- Current branch and working directory
- What's been completed
- What remains
- Any open decisions or assumptions

This serves two purposes: it forces a state reconciliation (catching drift), and it provides a handoff document if the session needs to continue later.

## Edit Discipline

### Read Before Editing

Never modify a file that hasn't been read in the current turn. When editing multiple files:

1. Read all target files first
2. Then edit them

After any context continuation, re-read files before editing — the in-memory version may be stale.

**Why this matters:** Editing from memory (or from a previous context window) risks clobbering changes made by other processes, other agents, or the user since the file was last read.

### Cross-Reference Before Copying

When duplicating or adapting files that exist in multiple variants (e.g., staging/production, sibling modules, parallel configs):

1. Diff all available variants against each other
2. Identify every discrepancy
3. For each discrepancy, verify whether it has any effect by tracing how the value is consumed
4. Only adopt changes from another variant after confirming they matter

A difference between variants is not automatically a bug — it may be intentional, or it may be dead code. Verify before assuming.

### Copy Files With File Operations

When duplicating files, use direct file reads and writes (or filesystem copy + targeted edits). Do not relay file contents through summaries or intermediary agents — inline comments, whitespace, and subtle formatting get silently stripped, causing cosmetic drift that obscures real diffs later.

## Diagnostics Discipline

### Fix Diagnostics Immediately

When IDE diagnostics, linter warnings, or build errors appear after a change, fix them in the same session before moving on. Do not classify warnings as "minor", "style-only", or "won't affect behavior" to avoid fixing them.

Every diagnostic is a finding. If it can't be fixed right now, flag it explicitly to the user — do not silently skip it.

**Why this matters:** Dismissing diagnostics creates a pattern of ignoring signals. Today's "harmless" warning becomes tomorrow's confusing failure when someone else inherits the code.

### Never Dismiss Unexpected Diffs

Every diff in a plan output, test result, or deployment comparison is a finding that must be investigated. Never dismiss unexpected changes as "not our change" or "pre-existing."

An unexpected diff means something **will change** on the next apply/deploy/merge — that's always relevant, regardless of what caused it.

## Failure Analysis Protocol

When investigating a CI/CD, infrastructure, or runtime failure:

### 1. Classify the Error Signature First

Before theorizing about root causes:

| Signature | Category | First Action |
| --------- | -------- | ------------ |
| EOF, timeout, connection reset | Transient | Recommend re-run |
| 403, Access Denied, unauthorized | Access/permissions | Check credentials and IAM |
| Connection refused, no route to host | Network | Check connectivity and endpoints |
| Exit code 1, assertion failed | Logic/code | Read the failing code and context |
| OOM, killed | Resources | Check resource limits and actual usage |

### 2. Try the Cheapest Diagnostic First

If the failure could be transient (cold start, timeout, flaky provider), recommend a re-run before deep investigation. Many failures are one-time events that don't warrant hours of analysis.

### 3. Diagnosis Before Implementation

Present a diagnosis and get confirmation before creating branches or editing files. An analysis task is not an implementation task unless the user explicitly says so.

### 4. Correlation Is Not Causation

Configuration differences found during investigation are **findings to report**, not automatic root causes. "This config differs between environments" is useful information, but it doesn't mean that difference caused the failure. Report the finding separately from the diagnosis.

## Destructive Operation Protocol

### Enumerate Before Destroying

When asked to "remove", "clean up", "delete", or "tear down":

1. Produce an explicit numbered list of exactly which resources will be affected
2. Get per-item or per-batch confirmation
3. Execute only confirmed items

Never infer scope from broad terms like "clean up everything" or "remove the old ones."

### Know the Intent: Remove Tracking vs Delete Resource

When removing infrastructure state:

| Intent                            | Operation                         | Effect                                         |
| --------------------------------- | --------------------------------- | ---------------------------------------------- |
| Delete the resource               | `destroy -target` (or equivalent) | Resource is destroyed                          |
| Stop tracking (resource lives on) | State removal (or equivalent)     | Resource continues to exist, no longer managed |

Always state which operation you're using and why. Confirm with the user before executing.

## Plan Mode Discipline

When a plan is rejected:

1. Ask what's missing — don't try to re-submit without addressing feedback
2. Present plans incrementally — don't dump a massive plan and hope for approval
3. Treat rejection as information, not failure

## Scope Creep Prevention

### Only Modify What's Requested

Before touching any file outside the explicit request scope:

1. State which file you intend to modify
2. Explain why
3. Wait for approval

Do not refactor, clean up, or "improve" code adjacent to your target. A bug fix doesn't need the surrounding code polished. A feature doesn't need extra configurability added.

### Analysis Tasks Are Not Implementation Tasks

When investigating a failure or reviewing code, the default output is a report — not a fix. Present findings and get explicit approval before transitioning from analysis to implementation. The user may want to fix it themselves, fix it differently, or defer it.

## Incident Response Speed

### Prefer Direct Tools Over IaC During Incidents

When resolving a live production issue, prioritize speed:

- **Use the fastest path to a working state** — During incidents, apply fixes directly (kubectl, CLI tools, console) rather than waiting for IaC applies that may timeout. A Helm release via Terraform can take 15+ minutes; a `kubectl patch` takes seconds.
- **IaC convergence happens after** — Once the immediate fix is verified, commit the code changes and let CI/CD converge the IaC state. The PR ensures long-term correctness; the direct fix ensures immediate availability.
- **Check early signals, don't wait for completion** — After applying a fix, verify by checking the first available signal (pod events, scheduling status, node provisioning). Don't block on a full deployment cycle to confirm a fix works.

### Mismatched Defaults Are Silent Killers

When a system has **two configuration surfaces that must agree** (e.g., a pod's nodeSelector and a node pool's capacity types, or a service's expected port and a load balancer's target port):

- **Always verify both sides** — A mismatch between producer and consumer configs causes silent failures (pods stuck in Pending, connections refused, etc.) that look like infrastructure problems but are configuration bugs.
- **Test the default path, not just overrides** — Many configs have defaults that are rarely exercised because overrides mask them. When no override exists, the default takes effect — verify it's correct.

## Git Isolation and History Hygiene

### Use git worktree for Isolated Git Work, Not cp -r

When you need an isolated copy of a repo to do safe rebase or branch work:

- **Use `git worktree add /tmp/wt-name branch-name`** — creates a fully functional working tree sharing the same git object store
- **Never use `cp -r`** — silently skips hidden directories (`.git`, `.claude`, `.github`, `.env`), and fails or hangs on deeply nested `node_modules`

If the branch is already checked out in the main worktree, worktree add will fail. In that case, the remote branch itself is the backup — proceed with `git reset --soft` or rebase in the main tree, knowing `git reset --hard origin/<branch>` restores everything.

### Squash Noisy Iteration Commits Before Merge

Before merging a PR, review the commit history. Multiple commits that all touch the same file iterating toward a correct result ("add rule", "clarify rule", "fix rule", "correct rule again") should be squashed into one clean commit:

```bash
git reset --soft HEAD~N          # N = number of commits to squash
git commit -m "docs: descriptive final message"
git push --force-with-lease
```

The remote branch is the safety net — if anything goes wrong, `git reset --hard origin/<branch>` restores the original state. `--force-with-lease` prevents accidentally overwriting someone else's concurrent push.

## State Management Safety

### Workspaces and Environments

Before any workspace or environment operation:

1. List existing workspaces/environments first
2. Present the proposed target and get approval
3. Never create new environments without confirmation

### Image Tags and Versions

Never rely on defaults like `latest`, `main`, or implicit version resolution:

1. Check what's actually running
2. Resolve available versions from the registry
3. Present options and get explicit selection

The default in code (e.g., `coalesce(var.image_tag, "main")`) is a fallback, not an instruction.
