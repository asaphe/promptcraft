#!/usr/bin/env bash
# Destructive operation guard — two-tier blocking system.
#
# HARD BLOCK (exit 2): Irreversible data loss. Cannot be overridden by
#   Bash(*) permissions. User must run the command themselves.
#   Examples: AWS resource deletion, git reset --hard, push to main.
#
# SOFT BLOCK (JSON + exit 0): Visible/risky actions that need confirmation.
#   Bash(*) permissions can override, allowing user to approve in the prompt.
#   Examples: PR create/close/merge, force-push, terraform destroy, kubectl delete.
#
# Install: add to settings.json under hooks.PreToolUse[].hooks[]
#   { "type": "command", "command": "/path/to/destructive-guard.sh" }
#
# Requires: jq, perl (for strip-cmd)

INPUT=$(cat)
HOOK_DIAG_NAME="destructive-guard"
source "$(dirname "$0")/../_lib/hook-diag.sh"
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

if [ -z "$CMD" ]; then
  exit 0
fi

# Strip heredoc bodies and -m args before pattern matching (shared util).
source "$(dirname "$0")/../_lib/strip-cmd.sh"
CMD_STRIPPED=$(strip_cmd "$CMD")

HARD_REASON=""
SOFT_REASON=""

# =====================================================================
# HARD BLOCKS — irreversible data loss, exit 2
# =====================================================================

# git push to main/master (bypass PR process). Pattern allows flags between
# `git` and `push` (e.g., `git -C dir push`, `git --git-dir=foo push`).
if echo "$CMD_STRIPPED" | grep -qE 'git[[:space:]]([^|;&]* )?push([[:space:]]|$)' && ! echo "$CMD_STRIPPED" | grep -qE 'git[[:space:]]([^|;&]* )?push.*--(force|force-with-lease)'; then
  # Determine the effective git directory — if the command does
  # "cd /tmp/worktree && ... && git push", check the branch there,
  # not in the hook's CWD (which stays on main per worktree rules).
  PUSH_DIR=""
  if echo "$CMD_STRIPPED" | grep -qE 'cd +[^ ;&]+ *[;&].*git[[:space:]]([^|;&]* )?push'; then
    PUSH_DIR=$(echo "$CMD" | grep -oE 'cd +[^ ;&]+' | tail -1 | sed 's/^cd *//')
  fi
  # `git -C <dir> push` form — extract <dir> as the effective directory.
  if [ -z "$PUSH_DIR" ] && echo "$CMD_STRIPPED" | grep -qE 'git +-C +[^ ]+[^;&|]*push'; then
    PUSH_DIR=$(echo "$CMD" | grep -oE 'git +-C +[^ ]+' | head -1 | awk '{print $NF}')
  fi

  # Extract the git push portion and determine what's being pushed.
  PUSH_PORTION=$(echo "$CMD" | grep -oE 'push[^;&|]*' | head -1)
  # Use awk to keep only words that don't start with "-" (flags like -u, --set-upstream).
  # Plain sed 's/--*[^ ]*//g' corrupts hyphenated branch names (main-hotfix → main).
  PUSH_REF=$(echo "$PUSH_PORTION" | sed 's/^push *//' | awk 'BEGIN{n=0} {for(i=1;i<=NF;i++) if(substr($i,1,1)!="-") {n++; if(n==2) {print $i; exit}}}')

  WILL_PUSH_MAIN=""
  if [ -z "$PUSH_REF" ]; then
    # No explicit ref — pushes current branch. Check which branch we're on.
    if [ -n "$PUSH_DIR" ]; then
      BRANCH=$(git -C "$PUSH_DIR" branch --show-current 2>/dev/null)
    else
      BRANCH=$(git branch --show-current 2>/dev/null)
    fi
    if [ "$BRANCH" = "main" ] || [ "$BRANCH" = "master" ]; then
      WILL_PUSH_MAIN=1
    fi
  elif [ "$PUSH_REF" = "main" ] || [ "$PUSH_REF" = "master" ]; then
    WILL_PUSH_MAIN=1
  elif echo "$PUSH_REF" | grep -qE '(^|[/:])(main|master)$'; then
    WILL_PUSH_MAIN=1
  fi

  if [ -n "$WILL_PUSH_MAIN" ]; then
    HARD_REASON="git push on main — changes must go through a PR. Create a branch first."
  fi
fi

# git clean -f (permanent deletion of untracked files)
if echo "$CMD_STRIPPED" | grep -qE 'git[[:space:]]([^|;&]* )?clean +-[a-zA-Z]*f'; then
  HARD_REASON="git clean -f — permanently deletes untracked files."
fi

# git stash drop/clear (permanent loss of stashed work)
if echo "$CMD_STRIPPED" | grep -qE 'git[[:space:]]([^|;&]* )?stash +(drop|clear)'; then
  HARD_REASON="git stash drop/clear — permanently discards stashed changes."
fi

# AWS resource deletion. Pattern allows flags between `aws` and the service
# (e.g., `aws --profile prod s3 rm`).
if echo "$CMD_STRIPPED" | grep -qE 'aws[[:space:]]([^|;&]* )?sqs +purge-queue([[:space:]]|$)'; then
  HARD_REASON="aws sqs purge-queue — permanently deletes all messages."
fi

if echo "$CMD_STRIPPED" | grep -qE 'aws[[:space:]]([^|;&]* )?sqs +delete-(queue|message)([[:space:]]|$)'; then
  HARD_REASON="aws sqs delete — permanently removes queue or messages."
fi

if echo "$CMD_STRIPPED" | grep -qE 'aws[[:space:]]([^|;&]* )?s3 +r(m|b)([[:space:]]|$)'; then
  HARD_REASON="aws s3 rm/rb — permanently deletes S3 objects or buckets."
fi

if echo "$CMD_STRIPPED" | grep -qE 'aws[[:space:]]([^|;&]* )?secretsmanager +delete-secret([[:space:]]|$)'; then
  HARD_REASON="aws secretsmanager delete-secret — permanently removes a secret."
fi

if echo "$CMD_STRIPPED" | grep -qE 'aws[[:space:]]([^|;&]* )?sns +delete-topic([[:space:]]|$)'; then
  HARD_REASON="aws sns delete-topic — permanently removes an SNS topic and all subscriptions."
fi

if echo "$CMD_STRIPPED" | grep -qE 'aws[[:space:]]([^|;&]* )?ecr +batch-delete-image([[:space:]]|$)'; then
  HARD_REASON="aws ecr batch-delete-image — permanently removes container images."
fi

if echo "$CMD_STRIPPED" | grep -qE 'aws[[:space:]]([^|;&]* )?rds +delete-db'; then
  HARD_REASON="aws rds delete — permanently removes a database instance or cluster."
fi

if echo "$CMD_STRIPPED" | grep -qE 'aws[[:space:]]([^|;&]* )?ec2 +terminate-instances([[:space:]]|$)'; then
  HARD_REASON="aws ec2 terminate-instances — permanently destroys EC2 instances."
fi

if echo "$CMD_STRIPPED" | grep -qE 'aws[[:space:]]([^|;&]* )?lambda +delete-function([[:space:]]|$)'; then
  HARD_REASON="aws lambda delete-function — permanently removes a Lambda function."
fi

if echo "$CMD_STRIPPED" | grep -qE 'aws[[:space:]]([^|;&]* )?iam +delete-(role|policy|user|group)([[:space:]]|$)'; then
  HARD_REASON="aws iam delete — permanently removes IAM resources."
fi

# Branch switching outside session directory — disrupts other sessions.
# Any git checkout/switch that changes branches in a repo other than the
# session's working directory must use worktrees instead.
if echo "$CMD_STRIPPED" | grep -qE 'git[[:space:]]([^|;&]* )?(checkout|switch)([[:space:]]|$)' && ! echo "$CMD_STRIPPED" | grep -qE 'git[[:space:]]([^|;&]* )?checkout +(-- |--$)'; then
  CMD_TARGET=""
  if echo "$CMD_STRIPPED" | grep -qE '^cd +[^ ;]+ *[;&]'; then
    CMD_TARGET=$(echo "$CMD" | grep -oE '^cd +[^ ;]+' | head -1 | sed 's/^cd *//')
  fi
  if echo "$CMD_STRIPPED" | grep -qE 'git +-C +'; then
    CMD_TARGET=$(echo "$CMD" | grep -oE '\-C +[^ ]+' | head -1 | sed 's/^-C *//')
  fi
  if [ -n "$CMD_TARGET" ]; then
    CMD_TARGET_ABS=$(cd "$CMD_TARGET" 2>/dev/null && pwd || echo "$CMD_TARGET")
    SESSION_CWD=$(pwd)
    # Use --git-common-dir to identify the repo — worktrees of the same repo
    # share a common git dir, so this correctly allows worktree checkouts
    SESSION_GIT=$(git -C "$SESSION_CWD" rev-parse --git-common-dir 2>/dev/null || echo "$SESSION_CWD")
    TARGET_GIT=$(git -C "$CMD_TARGET_ABS" rev-parse --git-common-dir 2>/dev/null || echo "$CMD_TARGET_ABS")
    SESSION_GIT=$(cd "$SESSION_CWD" && cd "$SESSION_GIT" 2>/dev/null && pwd || echo "$SESSION_GIT")
    TARGET_GIT=$(cd "$CMD_TARGET_ABS" && cd "$TARGET_GIT" 2>/dev/null && pwd || echo "$TARGET_GIT")
    if [ "$SESSION_GIT" != "$TARGET_GIT" ]; then
      SESSION_REPO=$(git -C "$SESSION_CWD" rev-parse --show-toplevel 2>/dev/null || echo "$SESSION_CWD")
      TARGET_REPO=$(git -C "$CMD_TARGET_ABS" rev-parse --show-toplevel 2>/dev/null || echo "$CMD_TARGET_ABS")
      HARD_REASON="Branch switch in ${TARGET_REPO} from a session in ${SESSION_REPO}. Use 'git worktree add /tmp/<name> -b <branch> main' instead."
    fi
  fi
fi

# =====================================================================
# SOFT BLOCKS — risky but approvable, JSON + exit 0
# =====================================================================

# GitHub CLI — visible shared actions. Pattern allows flags between `gh` and
# the subcommand (e.g., `gh --repo X pr create`).
if echo "$CMD_STRIPPED" | grep -qE 'gh[[:space:]]([^|;&]* )?pr +create([[:space:]]|$)'; then
  SOFT_REASON="gh pr create — creating a PR is a visible shared action. Confirm with the user first."
fi

if echo "$CMD_STRIPPED" | grep -qE 'gh[[:space:]]([^|;&]* )?pr +close([[:space:]]|$)'; then
  HARD_REASON="gh pr close — STOP. Cannot close PRs without explicit user instruction. Verify: (1) Read the PR fully, (2) Check for open review threads, (3) Confirm reason with user, (4) Verify no unmerged work will be lost."
fi

if echo "$CMD_STRIPPED" | grep -qE 'gh[[:space:]]([^|;&]* )?pr +merge([[:space:]]|$)'; then
  HARD_REASON="gh pr merge — STOP. Never merge a PR without explicit user instruction. The user merges PRs themselves."
fi

if echo "$CMD_STRIPPED" | grep -qE 'gh[[:space:]]([^|;&]* )?run +delete([[:space:]]|$)'; then
  SOFT_REASON="gh run delete — permanently removes CI run history."
fi

# Git — history rewriting (reversible via reflog)
if echo "$CMD_STRIPPED" | grep -qE 'git[[:space:]]([^|;&]* )?reset +--hard'; then
  SOFT_REASON="git reset --hard — discards uncommitted changes (recoverable via reflog)."
fi

if echo "$CMD_STRIPPED" | grep -qE 'git[[:space:]]([^|;&]* )?push +\S+ +:'; then
  SOFT_REASON="git push origin :branch — deletes a remote branch, which auto-closes any PR using it."
fi

if echo "$CMD_STRIPPED" | grep -qE 'git[[:space:]]([^|;&]* )?push.*--(force|force-with-lease)'; then
  SOFT_REASON="git push --force — rewrites remote history. Confirm with the user first."
fi

if echo "$CMD_STRIPPED" | grep -qE 'git[[:space:]]([^|;&]* )?branch +-D'; then
  SOFT_REASON="git branch -D — force-deletes a branch that may have unmerged work."
fi

if echo "$CMD_STRIPPED" | grep -qE 'git[[:space:]]([^|;&]* )?checkout +--'; then
  SOFT_REASON="git checkout -- — discards uncommitted file changes."
fi

if echo "$CMD_STRIPPED" | grep -qE 'git[[:space:]]([^|;&]* )?restore +' && ! echo "$CMD_STRIPPED" | grep -qE 'git[[:space:]]([^|;&]* )?restore +--staged'; then
  SOFT_REASON="git restore — discards uncommitted file changes."
fi

# Terraform — destructive but plan shows impact
if echo "$CMD_STRIPPED" | grep -qE 'terraform +destroy'; then
  SOFT_REASON="terraform destroy — destroys all resources in the workspace."
fi

if echo "$CMD_STRIPPED" | grep -qE 'terraform +state +rm'; then
  SOFT_REASON="terraform state rm — removes resources from state, orphaning them."
fi

if echo "$CMD_STRIPPED" | grep -qE 'terraform +force-unlock'; then
  SOFT_REASON="terraform force-unlock — breaks state locks that may protect concurrent operations."
fi

if echo "$CMD_STRIPPED" | grep -qE 'terraform +workspace +delete'; then
  SOFT_REASON="terraform workspace delete — permanently removes a workspace and its state."
fi

# Kubectl — pattern allows flags between `kubectl` and the verb. Token group
# excludes command separators (|;&) so a downstream pipe like
# `kubectl get | grep delete` does not false-positive.
if echo "$CMD_STRIPPED" | grep -qE 'kubectl[[:space:]]([^|;&]* )?delete([[:space:]]|$)'; then
  SOFT_REASON="kubectl delete — permanently removes Kubernetes resources."
fi

if echo "$CMD_STRIPPED" | grep -qE 'kubectl[[:space:]]([^|;&]* )?drain([[:space:]]|$)'; then
  SOFT_REASON="kubectl drain — evicts all pods from a node."
fi

if echo "$CMD_STRIPPED" | grep -qE 'kubectl[[:space:]]([^|;&]* )?cordon([[:space:]]|$)'; then
  SOFT_REASON="kubectl cordon — prevents new pods from scheduling on a node."
fi

if echo "$CMD_STRIPPED" | grep -qE 'kubectl[[:space:]]([^|;&]* )?scale([[:space:]]|$)'; then
  SOFT_REASON="kubectl scale — changes replica count, affecting live traffic."
fi

if echo "$CMD_STRIPPED" | grep -qE 'kubectl[[:space:]]([^|;&]* )?rollout +undo([[:space:]]|$)'; then
  SOFT_REASON="kubectl rollout undo — reverts a deployment to a previous revision."
fi

if echo "$CMD_STRIPPED" | grep -qE 'kubectl[[:space:]]([^|;&]* )?patch([[:space:]]|$)'; then
  SOFT_REASON="kubectl patch — mutates live Kubernetes resources."
fi

# Helm — same pattern shape as kubectl
if echo "$CMD_STRIPPED" | grep -qE 'helm[[:space:]]([^|;&]* )?uninstall([[:space:]]|$)'; then
  SOFT_REASON="helm uninstall — removes a Helm release and all its resources."
fi

if echo "$CMD_STRIPPED" | grep -qE 'helm[[:space:]]([^|;&]* )?rollback([[:space:]]|$)'; then
  SOFT_REASON="helm rollback — reverts a release to a previous revision."
fi

# =====================================================================
# Apply blocks — hard wins over soft
# =====================================================================

if [ -n "$HARD_REASON" ]; then
  echo "$HARD_REASON" >&2
  exit 2
fi

if [ -n "$SOFT_REASON" ]; then
  echo "$SOFT_REASON" >&2
  exit 1
fi

exit 0
