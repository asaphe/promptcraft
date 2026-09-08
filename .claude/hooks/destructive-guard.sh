#!/usr/bin/env bash
# Destructive operation guard — two-tier blocking system.
#
# HARD BLOCK (stderr + exit 2): Irreversible data loss or forbidden shared-state
#   actions. Cannot be overridden by Bash(*) permissions. User must run the
#   command themselves.
#   Examples: AWS resource deletion, push/force-push to main, gh pr close/merge.
#
# SOFT BLOCK (JSON permissionDecision "ask" + exit 0): Visible/risky actions
#   that need confirmation. Emits hookSpecificOutput JSON on stdout so Claude
#   Code prompts the user, who can approve in the permission prompt.
#   Examples: PR create, force-push to a feature branch, terraform destroy,
#   kubectl delete, git reset --hard.
#
# Install: add to settings.json under hooks.PreToolUse[].hooks[]
#   { "type": "command", "command": "/path/to/destructive-guard.sh" }
#
# Requires: jq, perl (for strip-cmd)

INPUT=$(cat)
# shellcheck disable=SC2034  # read by the sourced hook-diag.sh
HOOK_DIAG_NAME="destructive-guard"
# Fail CLOSED on a missing dependency: without jq or perl this guard matches nothing and passes everything.
for _dep in jq perl; do
  if ! command -v "$_dep" >/dev/null 2>&1; then
    echo "destructive-guard: '$_dep' not on PATH — refusing to run rather than passing every command unchecked. This blocks every Bash call until it is resolved: install '$_dep', or unregister this hook in settings.json (hooks.PreToolUse)." >&2
    exit 2
  fi
done
source "$(dirname "$0")/../_lib/hook-diag.sh"
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

if [ -z "$CMD" ]; then
  exit 0
fi

# Strip heredoc bodies and -m args before pattern matching (shared util).
source "$(dirname "$0")/../_lib/strip-cmd.sh"
CMD_STRIPPED=$(strip_cmd "$CMD")
# A tab or a backslash-continuation between tokens defeats every ` +` here; builtins, not another perl fork.
CMD_STRIPPED="${CMD_STRIPPED//\\$'\n'/ }"
CMD_STRIPPED="${CMD_STRIPPED//$'\t'/ }"
# see: README.md § Parser hardening — a quoted whitespace-free token IS that token, so `"gh" pr merge` is a merge
CMD_STRIPPED=$(printf '%s' "$CMD_STRIPPED" | sed -E 's/"([^"'"'"'[:space:]]+)"/\1/g; s/'"'"'([^"'"'"'[:space:]]+)'"'"'/\1/g')

# see: README.md § Parser hardening — matching runs on a copy with quoted DATA blanked; extraction keeps real values
CMD_MATCH=$(strip_quoted_args "$CMD_STRIPPED")

# Extraction patterns exclude spaces and separators, not quotes, so `cd "path" &&` keeps its quotes.
unquote() {
  local p="$1"
  p="${p%\"}"; p="${p#\"}"
  p="${p%\'}"; p="${p#\'}"
  printf '%s' "$p"
}

# A path extracted from command TEXT is never shell-expanded, so `~/repo` stays literal.
# see: tools/claude/examples/hooks/destructive-guard/README.md § Parser hardening — an unexpanded path fails OPEN, not closed
expand_path() {
  local p="$1"
  [ "$p" = "~" ] && { printf '%s' "$HOME"; return; }
  p="${p/#\~\//$HOME/}"
  p="${p//\$\{HOME\}/$HOME}"
  p="${p//\$HOME/$HOME}"
  printf '%s' "$p"
}

# see: tools/claude/examples/hooks/destructive-guard/README.md § Parser hardening — token walk, and why separators are isolated first
push_args() {
  printf '%s\n' "$1" | sed 's/[;&|]/ & /g' | awk '{
    out = ""; seen = 0
    for (i = 1; i <= NF; i++) {
      if (seen) { if ($i ~ /^[;&|]$/) break; out = out (out == "" ? "" : " ") $i }
      else if ($i == "push") seen = 1
    }
    print out
  }'
}

# Newlines flattened: every pattern below is line-scoped, so a construct split across lines matched nothing.
CMD_FLAT=$(printf '%s' "$CMD_STRIPPED" | tr '\n' ';')
# The matching twin, so a loop or `cd` quoted inside an echo is prose rather than a construct.
CMD_FLAT_MATCH=$(printf '%s' "$CMD_MATCH" | tr '\n' ';')

SPLIT_SEGMENTS="$(dirname "$0")/../_lib/split-cmd-segments.pl"

# see: README.md § Parser hardening — loaded once into an array; three callers meant three perl forks
_SEGS_LOADED=""
_SEGS=()
load_segments() {
  [ -n "$_SEGS_LOADED" ] && return 0
  _SEGS_LOADED=1
  if [ -r "$SPLIT_SEGMENTS" ]; then
    local seg
    while IFS= read -r -d '' seg; do _SEGS[${#_SEGS[@]}]="$seg"; done \
      < <(printf '%s' "$CMD_MATCH" | perl "$SPLIT_SEGMENTS")
  else
    # Degrading to whole-command matching is correct, but silent degradation is not observable.
    _SEGS[0]="$CMD_MATCH"
    hook_diag_event SPLITTER_MISSING "$SPLIT_SEGMENTS"
  fi
}

# seg_matches <negative> <required>... — true when ONE segment matches every <required> and not <negative>.
# see: tools/claude/examples/hooks/destructive-guard/README.md § Parser hardening — why a whole-command negative test is disarmable
seg_matches() {
  local negative="$1" seg pat ok
  shift
  load_segments
  for seg in "${_SEGS[@]}"; do
    ok=1
    for pat in "$@"; do
      printf '%s' "$seg" | grep -qE "$pat" || { ok=0; break; }
    done
    [ "$ok" = 1 ] || continue
    if [ -n "$negative" ] && printf '%s' "$seg" | grep -qE "$negative"; then
      continue
    fi
    return 0
  done
  return 1
}

# see: README.md § Cost per call — every rule keys on one of these; check-guard-gate.py fails CI if one is missing
GUARD_TOOLS='git|gh|aws|kubectl|helm|terraform|xargs'
if ! echo "$CMD_MATCH" | grep -qE "(^|[^[:alnum:]_.-])(${GUARD_TOOLS})([[:space:]]|$)"; then
  exit 0
fi

HARD_REASON=""
SOFT_REASON=""

# see: README.md § Reporting every trigger — last-writer-wins hid the graver of two soft triggers
add_soft() {
  case "$SOFT_REASON" in
    *"$1"*) return 0 ;;
  esac
  if [ -z "$SOFT_REASON" ]; then
    SOFT_REASON="$1"
  else
    SOFT_REASON="${SOFT_REASON}
ALSO: $1"
  fi
}

# =====================================================================
# HARD BLOCKS — irreversible data loss or forbidden shared-state ops, exit 2
# =====================================================================

# git push targeting main/master (bypass PR process). Plain pushes and force
# pushes are both checked: force-push to main/master hard-blocks with its own
# message; force-push to other refs falls through to the soft tier below.
# Pattern allows flags between `git` and `push` (e.g., `git -C dir push`).
if echo "$CMD_MATCH" | grep -qE 'git[[:space:]]([^|;&]* )?push([[:space:]]|$)'; then
  # Determine the effective git directory — if the command does
  # "cd /tmp/worktree && ... && git push", check the branch there,
  # not in the hook's CWD (which stays on main per worktree rules).
  PUSH_DIR=""
  if echo "$CMD_FLAT_MATCH" | grep -qE 'cd +[^ ;&]+ *[;&].*git[[:space:]]([^|;&]* )?push'; then
    PUSH_DIR=$(printf '%s' "$CMD_FLAT" | grep -oE 'cd +[^ ;&]+' | tail -1 | sed 's/^cd *//')
  fi
  # `git -C <dir> push` form — extract <dir> as the effective directory.
  if [ -z "$PUSH_DIR" ] && echo "$CMD_MATCH" | grep -qE 'git +-C +[^ ]+[^;&|]*push'; then
    PUSH_DIR=$(echo "$CMD_STRIPPED" | grep -oE 'git +-C +[^ ]+' | head -1 | awk '{print $NF}')
  fi
  PUSH_DIR=$(expand_path "$(unquote "$PUSH_DIR")")

  # Per segment, not once per command: an earlier bare `push` — in an echo, a grep, a message —
  # otherwise captured the extraction and hid the real `git push` in a later segment.
  load_segments
  for PUSH_SEGMENT in "${_SEGS[@]}"; do
    echo "$PUSH_SEGMENT" | grep -qE 'git[[:space:]]([^|;&]* )?push([[:space:]]|$)' || continue
    PUSH_PORTION=$(push_args "$PUSH_SEGMENT")
    # Keep only words that don't start with "-"; plain sed 's/--*[^ ]*//g' corrupts main-hotfix → main.
    PUSH_REF=$(echo "$PUSH_PORTION" | awk 'BEGIN{n=0} {for(i=1;i<=NF;i++) if(substr($i,1,1)!="-") {n++; if(n==2) {print $i; exit}}}')
    # Quotes survive extraction, and `"main"` compares equal to nothing.
    PUSH_REF=$(unquote "$PUSH_REF")
    # A leading `+` is the force marker, not part of the ref name, so `+main` still reads as main.
    PUSH_REF="${PUSH_REF#+}"
    # Bare HEAD names no branch, so it must fall through to the branch lookup rather than read as a ref.
    [ "$PUSH_REF" = "HEAD" ] && PUSH_REF=""

    WILL_PUSH_MAIN=""
    if [ -z "$PUSH_REF" ]; then
      # A failed cd does not stop the push — it runs in the session cwd, so an unusable PUSH_DIR
      # must fall back there rather than leave an empty branch that reads as "not main".
      BRANCH=""
      if [ -n "$PUSH_DIR" ] && git -C "$PUSH_DIR" rev-parse --git-dir >/dev/null 2>&1; then
        BRANCH=$(git -C "$PUSH_DIR" branch --show-current 2>/dev/null)
      fi
      if [ -z "$BRANCH" ]; then
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
      # Force flags: --force, --force-with-lease(=ref), or short -f (possibly bundled, e.g. -uf).
      if echo "$PUSH_PORTION" | grep -qE '(^|[[:space:]])(--force(-with-lease)?(=[^[:space:]]*)?|-[a-zA-Z]*f[a-zA-Z]*)([[:space:]]|$)'; then
        HARD_REASON="git push --force to main — rewrites shared history on the default branch."
      else
        HARD_REASON="git push on main — changes must go through a PR. Create a branch first."
      fi
      break
    fi
  done
fi

# see: tools/claude/examples/hooks/destructive-guard/README.md § Why `--dry-run` is not exempt — an exemption is satisfiable by an earlier segment
if echo "$CMD_MATCH" | grep -qE 'git[[:space:]]([^|;&]* )?clean[^|;&]*[[:space:]](--force|-[a-zA-Z]*f[a-zA-Z]*)([[:space:]]|=|$)'; then
  HARD_REASON="git clean -f/--force — permanently deletes untracked files."
fi

# git stash drop/clear (permanent loss of stashed work)
if echo "$CMD_MATCH" | grep -qE 'git[[:space:]]([^|;&]* )?stash +(drop|clear)'; then
  HARD_REASON="git stash drop/clear — permanently discards stashed changes."
fi

# see: tools/claude/examples/hooks/destructive-guard/README.md § Bulk branch deletion — why blast radius, not the delete, makes these hard
BULK_BRANCH_MSG="bulk branch deletion is a hard block in BOTH the -d and -D forms — retrying with -d will not pass. Delete one branch at a time, confirming each with the user, or have the user run the bulk command themselves."
if echo "$CMD_FLAT_MATCH" | grep -qE 'xargs[^|;&]*git[[:space:]]([^|;&]* )?branch +-[Dd]'; then
  HARD_REASON="xargs git branch -d/-D — ${BULK_BRANCH_MSG}"
fi

# The body between `do` and `done` is extracted, not matched across: a multi-line body puts arbitrarily many separators in the way, and `done && git branch -d x` is not a bulk delete.
if echo "$CMD_FLAT_MATCH" | grep -qE '(for[[:space:]]|while[[:space:]])'; then
  # Non-greedy and repeated: a greedy match anchors on the LAST `do`, so a second loop disarmed this.
  LOOP_BODY=$(printf '%s' "$CMD_FLAT_MATCH" \
    | perl -0777 -ne 'while (/\sdo[\s;&]+(.*?)[\s;&]done/gs) { print "$1\n" }')
  if printf '%s' "$LOOP_BODY" | grep -qE 'git[[:space:]]([^|;&]* )?branch +-[Dd]'; then
    HARD_REASON="for/while loop with git branch -d/-D — ${BULK_BRANCH_MSG}"
  fi
fi

# `(-- +)?` because `git branch -D -- a b` is the same bulk delete with an end-of-options marker.
if echo "$CMD_FLAT_MATCH" | grep -qE 'git[[:space:]]([^|;&]* )?branch +-[Dd] +(-- +)?[^ |;&<>-][^ |;&<>]* +[^ |;&<>-][^ |;&<>]*([[:space:]]|;|$)'; then
  HARD_REASON="git branch -d/-D with multiple branches in one command — ${BULK_BRANCH_MSG}"
fi

# AWS resource deletion. Pattern allows flags between `aws` and the service
# (e.g., `aws --profile prod s3 rm`).
if echo "$CMD_MATCH" | grep -qE 'aws[[:space:]]([^|;&]* )?sqs +purge-queue([[:space:]]|$)'; then
  HARD_REASON="aws sqs purge-queue — permanently deletes all messages."
fi

if echo "$CMD_MATCH" | grep -qE 'aws[[:space:]]([^|;&]* )?sqs +delete-(queue|message)([[:space:]]|$)'; then
  HARD_REASON="aws sqs delete — permanently removes queue or messages."
fi

if echo "$CMD_MATCH" | grep -qE 'aws[[:space:]]([^|;&]* )?s3 +r(m|b)([[:space:]]|$)'; then
  HARD_REASON="aws s3 rm/rb — permanently deletes S3 objects or buckets."
fi

if echo "$CMD_MATCH" | grep -qE 'aws[[:space:]]([^|;&]* )?secretsmanager +delete-secret([[:space:]]|$)'; then
  HARD_REASON="aws secretsmanager delete-secret — permanently removes a secret."
fi

if echo "$CMD_MATCH" | grep -qE 'aws[[:space:]]([^|;&]* )?sns +delete-topic([[:space:]]|$)'; then
  HARD_REASON="aws sns delete-topic — permanently removes an SNS topic and all subscriptions."
fi

if echo "$CMD_MATCH" | grep -qE 'aws[[:space:]]([^|;&]* )?ecr +batch-delete-image([[:space:]]|$)'; then
  HARD_REASON="aws ecr batch-delete-image — permanently removes container images."
fi

if echo "$CMD_MATCH" | grep -qE 'aws[[:space:]]([^|;&]* )?rds +delete-db'; then
  HARD_REASON="aws rds delete — permanently removes a database instance or cluster."
fi

if echo "$CMD_MATCH" | grep -qE 'aws[[:space:]]([^|;&]* )?ec2 +terminate-instances([[:space:]]|$)'; then
  HARD_REASON="aws ec2 terminate-instances — permanently destroys EC2 instances."
fi

if echo "$CMD_MATCH" | grep -qE 'aws[[:space:]]([^|;&]* )?lambda +delete-function([[:space:]]|$)'; then
  HARD_REASON="aws lambda delete-function — permanently removes a Lambda function."
fi

if echo "$CMD_MATCH" | grep -qE 'aws[[:space:]]([^|;&]* )?iam +delete-(role|policy|user|group)([[:space:]]|$)'; then
  HARD_REASON="aws iam delete — permanently removes IAM resources."
fi

# see: tools/claude/examples/hooks/destructive-guard/README.md § AWS coverage — why this list is short and the soft catch-all does the rest
AWS_CATASTROPHIC='dynamodb +delete-(table|backup)'\
'|kms +schedule-key-deletion'\
'|s3api +delete-(object|objects|bucket)'\
'|eks +delete-(cluster|nodegroup|fargate-profile)'\
'|cloudformation +delete-stack'\
'|logs +delete-log-(group|stream)'\
'|ec2 +delete-(volume|snapshot)'\
'|efs +delete-file-system'\
'|elasticache +delete-(cache-cluster|replication-group)'\
'|redshift +delete-cluster'\
'|backup +delete-(recovery-point|backup-vault)'
if echo "$CMD_MATCH" | grep -qE "aws[[:space:]]([^|;&]* )?(${AWS_CATASTROPHIC})([[:space:]]|\$)"; then
  HARD_REASON="aws — irreversible destruction of stored data, its backups, or the KMS key that decrypts it. No approval path: confirm profile, account and exact resource, then run it yourself."
fi

# GitHub PR close/merge — shared PR state; deliberately hard so an allow-list
# cannot auto-approve them. Pattern allows flags between `gh` and the subcommand.
if echo "$CMD_MATCH" | grep -qE 'gh[[:space:]]([^|;&]* )?pr +close([[:space:]]|$)'; then
  HARD_REASON="gh pr close — STOP. Cannot close PRs without explicit user instruction. Verify: (1) Read the PR fully, (2) Check for open review threads, (3) Confirm reason with user, (4) Verify no unmerged work will be lost."
fi

MERGE_FORMS="All three merge forms are blocked with no approval path: 'gh pr merge', 'gh api .../pulls/N/merge', 'gh stack merge'."

if echo "$CMD_MATCH" | grep -qE 'gh[[:space:]]([^|;&]* )?pr +merge([[:space:]]|$)'; then
  HARD_REASON="gh pr merge — STOP. Never merge a PR without explicit user instruction. The user merges PRs themselves. ${MERGE_FORMS}"
fi

# The REST route reaches the same merge; an explicit GET is the read-only merged-status check, and the ref segment accepts a variable.
if seg_matches '(-X|--method)[[:space:]]+GET([[:space:]]|$)' \
   'gh[[:space:]]([^|;&]* )?api[^|;&]*/pulls/[^/[:space:]]+/merge(-async)?/?([^[:alnum:]/-]|$)'; then
  HARD_REASON="gh api .../pulls/N/merge — STOP. This is the REST form of the same forbidden action, covering the async variant too; there is no approval path. The user merges PRs themselves. ${MERGE_FORMS}"
fi

# Wider than the other two: it lands the target layer plus every unmerged layer beneath it.
if echo "$CMD_MATCH" | grep -qE 'gh[[:space:]]([^|;&]* )?stack +merge([[:space:]]|$)'; then
  HARD_REASON="gh stack merge — STOP. This is the stacked-PR form of the same forbidden action, and it lands EVERY unmerged layer beneath the target in one operation. There is no approval path. ${MERGE_FORMS}"
fi

# Branch switching outside session directory — disrupts other sessions.
# Any git checkout/switch that changes branches in a repo other than the
# session's working directory must use worktrees instead.
# see: README.md § Parser hardening — the effective directory is whatever the LAST cd set, per segment
CHECKOUT_CWD=""
load_segments
for CO_SEG in "${_SEGS[@]}"; do
  # A `cd` moves the effective directory for every segment after it, exactly as the shell does.
  case "$CO_SEG" in
    cd\ *) CHECKOUT_CWD=$(printf '%s' "$CO_SEG" | sed -E 's/^cd +([^ ;]+).*/\1/') ;;
  esac
  echo "$CO_SEG" | grep -qE 'git[[:space:]]([^|;&]* )?(checkout|switch)([[:space:]]|$)' || continue
  echo "$CO_SEG" | grep -qE 'git[[:space:]]([^|;&]* )?checkout +(-- |--$)' && continue

  # The -C belonging to THIS invocation, not the first one anywhere in the command.
  if echo "$CO_SEG" | grep -qE 'git +-C +'; then
    CMD_TARGET=$(echo "$CO_SEG" | grep -oE '\-C +[^ ]+' | head -1 | sed 's/^-C *//')
  else
    CMD_TARGET="$CHECKOUT_CWD"
  fi
  CMD_TARGET=$(expand_path "$(unquote "$CMD_TARGET")")
  if [ -n "$CMD_TARGET" ]; then
    CMD_TARGET_ABS=$(cd "$CMD_TARGET" 2>/dev/null && pwd || echo "$CMD_TARGET")
    SESSION_CWD=$(pwd)
    # Use --git-common-dir to identify the repo — worktrees of the same repo
    # share a common git dir, so this correctly allows worktree checkouts
    SESSION_GIT=$(git -C "$SESSION_CWD" rev-parse --git-common-dir 2>/dev/null || echo "$SESSION_CWD")
    TARGET_GIT=$(git -C "$CMD_TARGET_ABS" rev-parse --git-common-dir 2>/dev/null || echo "$CMD_TARGET_ABS")
    SESSION_GIT=$(cd "$SESSION_CWD" 2>/dev/null && cd "$SESSION_GIT" 2>/dev/null && pwd || echo "$SESSION_GIT")
    TARGET_GIT=$(cd "$CMD_TARGET_ABS" 2>/dev/null && cd "$TARGET_GIT" 2>/dev/null && pwd || echo "$TARGET_GIT")
    # A non-repo target never compares equal, so without this every `cd <non-repo> && git checkout` blocked.
    if [ "$SESSION_GIT" != "$TARGET_GIT" ] && git -C "$CMD_TARGET_ABS" rev-parse --git-dir >/dev/null 2>&1; then
      SESSION_REPO=$(git -C "$SESSION_CWD" rev-parse --show-toplevel 2>/dev/null || echo "$SESSION_CWD")
      TARGET_REPO=$(git -C "$CMD_TARGET_ABS" rev-parse --show-toplevel 2>/dev/null || echo "$CMD_TARGET_ABS")
      HARD_REASON="Branch switch in ${TARGET_REPO} from a session in ${SESSION_REPO}. Use 'git -C <repo> worktree add /tmp/<name> -b <branch> main' instead — pass -C explicitly, since a preceding cd that fails silently targets the session's repo."
      break
    fi
  fi
done

# =====================================================================
# SOFT BLOCKS — risky but approvable, JSON permissionDecision ask + exit 0
# =====================================================================

# GitHub CLI — visible shared actions. Pattern allows flags between `gh` and
# the subcommand (e.g., `gh --repo X pr create`).
if echo "$CMD_MATCH" | grep -qE 'gh[[:space:]]([^|;&]* )?pr +create([[:space:]]|$)'; then
  add_soft "gh pr create — creating a PR is a visible shared action. Confirm with the user first."
fi

# A wider `pr create`: it creates or re-links EVERY layer of the stack in one visible action.
if echo "$CMD_MATCH" | grep -qE 'gh[[:space:]]([^|;&]* )?stack +(submit|link)([[:space:]]|$)'; then
  add_soft "gh stack submit/link — creates or re-links every pull request in the stack, not one PR. Confirm with the user first, and check each layer's branch name against your branch-protection rules before pushing: auto-generated layer names are often rejected."
fi

if echo "$CMD_MATCH" | grep -qE 'gh[[:space:]]([^|;&]* )?stack +unstack([[:space:]]|$)'; then
  add_soft "gh stack unstack — removes the stack on GitHub, retargeting PRs other people may be reviewing. Pass --local to unlink only the local tracking."
fi

if echo "$CMD_MATCH" | grep -qE 'gh[[:space:]]([^|;&]* )?run +delete([[:space:]]|$)'; then
  add_soft "gh run delete — permanently removes CI run history."
fi

# Git — history rewriting (reversible via reflog)
if echo "$CMD_MATCH" | grep -qE 'git[[:space:]]([^|;&]* )?reset +--hard'; then
  add_soft "git reset --hard — discards uncommitted changes (recoverable via reflog)."
fi

# see: tools/claude/examples/hooks/destructive-guard/README.md § Parser hardening — `[^|;&]*` confines each test to the segment its push owns
PUSH_SEG='git[[:space:]]([^|;&]* )?push[^|;&]*[[:space:]]'

# Both spellings of one act: matching only the colon refspec left `push --delete origin br` unguarded.
if echo "$CMD_MATCH" | grep -qE 'git[[:space:]]([^|;&]* )?push +[^ |;&]+ +:' \
   || echo "$CMD_MATCH" | grep -qE "${PUSH_SEG}(--delete|-d)([[:space:]]|\$)"; then
  add_soft "git push origin :branch — deletes a remote branch, which auto-closes any PR using it. Covers both spellings: the colon refspec and --delete/-d."
fi

# `-f`, a bundled `-uf` and a `+refspec` are force-pushes too; matching only `--force` left them unguarded.
if echo "$CMD_MATCH" | grep -qE "${PUSH_SEG}(--force(-with-lease)?(=[^[:space:]]*)?|-[a-zA-Z]*f[a-zA-Z]*|\+[A-Za-z0-9._/:-]+)([[:space:]]|\$)"; then
  add_soft "git push --force — rewrites remote history (also matches -f and +refspec). Confirm with the user first."
fi

if echo "$CMD_MATCH" | grep -qE 'git[[:space:]]([^|;&]* )?branch +-D'; then
  add_soft "git branch -D — force-deletes a branch that may have unmerged work."
fi

if seg_matches '' 'git[[:space:]]([^|;&]* )?checkout +--'; then
  add_soft "git checkout -- — discards uncommitted file changes."
fi

if seg_matches 'git[[:space:]]([^|;&]* )?restore +--staged' 'git[[:space:]]([^|;&]* )?restore +'; then
  add_soft "git restore — discards uncommitted file changes."
fi

# `-chdir=` sits between binary and verb, so `terraform -chdir=infra destroy` read as unrecognised.
TF_CHDIR='terraform +(-chdir=[^ ]+ +)*'
if echo "$CMD_MATCH" | grep -qE "${TF_CHDIR}destroy"; then
  add_soft "terraform destroy — destroys all resources in the workspace."
fi

# `apply -destroy` is the same operation under a different verb, and the verb is what most rules key on.
if echo "$CMD_MATCH" | grep -qE "${TF_CHDIR}apply[^|;&]*[[:space:]]-destroy([[:space:]]|$)"; then
  add_soft "terraform apply -destroy — the same whole-workspace destroy, spelled as an apply."
fi

if echo "$CMD_MATCH" | grep -qE "${TF_CHDIR}state +rm"; then
  add_soft "terraform state rm — removes resources from state, orphaning them."
fi

if echo "$CMD_MATCH" | grep -qE "${TF_CHDIR}force-unlock"; then
  add_soft "terraform force-unlock — breaks state locks that may protect concurrent operations."
fi

if echo "$CMD_MATCH" | grep -qE "${TF_CHDIR}workspace +delete"; then
  add_soft "terraform workspace delete — permanently removes a workspace and its state."
fi

# Kubectl — pattern allows flags between `kubectl` and the verb. Token group
# excludes command separators (|;&) so a downstream pipe like
# `kubectl get | grep delete` does not false-positive.
if echo "$CMD_MATCH" | grep -qE 'kubectl[[:space:]]([^|;&]* )?delete([[:space:]]|$)'; then
  add_soft "kubectl delete — permanently removes Kubernetes resources."
fi

if echo "$CMD_MATCH" | grep -qE 'kubectl[[:space:]]([^|;&]* )?drain([[:space:]]|$)'; then
  add_soft "kubectl drain — evicts all pods from a node."
fi

if echo "$CMD_MATCH" | grep -qE 'kubectl[[:space:]]([^|;&]* )?cordon([[:space:]]|$)'; then
  add_soft "kubectl cordon — prevents new pods from scheduling on a node."
fi

if echo "$CMD_MATCH" | grep -qE 'kubectl[[:space:]]([^|;&]* )?scale([[:space:]]|$)'; then
  add_soft "kubectl scale — changes replica count, affecting live traffic."
fi

if echo "$CMD_MATCH" | grep -qE 'kubectl[[:space:]]([^|;&]* )?rollout +undo([[:space:]]|$)'; then
  add_soft "kubectl rollout undo — reverts a deployment to a previous revision."
fi

if echo "$CMD_MATCH" | grep -qE 'kubectl[[:space:]]([^|;&]* )?patch([[:space:]]|$)'; then
  add_soft "kubectl patch — mutates live Kubernetes resources."
fi

# Helm — same pattern shape as kubectl
if echo "$CMD_MATCH" | grep -qE 'helm[[:space:]]([^|;&]* )?uninstall([[:space:]]|$)'; then
  add_soft "helm uninstall — removes a Helm release and all its resources."
fi

if echo "$CMD_MATCH" | grep -qE 'helm[[:space:]]([^|;&]* )?rollback([[:space:]]|$)'; then
  add_soft "helm rollback — reverts a release to a previous revision."
fi

# see: tools/claude/examples/hooks/destructive-guard/README.md § AWS coverage — membership in the destructive-verb family, not in a hand-kept list
if echo "$CMD_MATCH" | grep -qE 'aws[[:space:]]([^|;&]* )?[a-z][a-z0-9-]*[[:space:]]+(delete|remove|terminate|purge|deregister|destroy)-[a-z0-9-]+'; then
  add_soft "aws destructive verb (delete-/remove-/terminate-/purge-/deregister-/destroy-). Confirm the profile, account and exact resource before approving."
fi

# Read-only verbs are the allowlist, so a verb a future gh release adds asks instead of passing silently.
if seg_matches 'gh[[:space:]]([^|;&]* )?issue[[:space:]]+(list|view|status)([[:space:]]|$)' \
   'gh[[:space:]]([^|;&]* )?issue[[:space:]]+[a-z][a-z-]*([[:space:]]|$)'; then
  add_soft "gh issue <mutating verb> — create/comment/edit/close/reopen/delete/transfer/pin/lock all file or alter an external artifact under your GitHub identity. Only run when the user asked for it by name; producing the content is not authorisation to publish it. Read-only list/view/status are unaffected."
fi

# The REST form of the same mutation; a plain GET on /issues stays allowed, including the search endpoint.
if seg_matches '(-X|--method)[[:space:]]+GET([[:space:]]|$)|[[:space:]]search/issues' \
   'gh[[:space:]]([^|;&]* )?api[^|;&]*/issues' \
   '(-X|--method)[[:space:]]+(POST|PATCH|PUT|DELETE)|[[:space:]](-f|-F|--field|--raw-field|--input)[[:space:]]'; then
  add_soft "gh api .../issues with a mutating method or field — the REST form of gh issue create/comment/edit, subject to the same rule: only when the user asked for it by name. A read-only GET on /issues is unaffected."
fi

# =====================================================================
# Apply blocks — hard wins over soft
# =====================================================================

if [ -n "$HARD_REASON" ]; then
  echo "$HARD_REASON" >&2
  exit 2
fi

if [ -n "$SOFT_REASON" ]; then
  # Label with the trigger (the text before the em-dash) so ask volume is tunable per trigger.
  # shellcheck disable=SC2034  # read by the sourced hook-diag.sh
  HOOK_DIAG_DECISION="ask:$(printf '%s' "${SOFT_REASON%% —*}" | tr -d '\n' | cut -c1-40)"
  jq -n \
    --arg reason "$SOFT_REASON" \
    '{
      "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "ask",
        "permissionDecisionReason": $reason
      }
    }'
  exit 0
fi

exit 0
