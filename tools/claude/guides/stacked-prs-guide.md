# Stacked Pull Requests

Read before splitting dependent work across more than one PR. GitHub shipped native stacked pull requests, driven from the CLI by the `gh-stack` extension; they entered public preview on 2026-07-31.

Availability is per-org, and preview features change, so probe your own org rather than trusting a changelog or this page:

```bash
gh api graphql -f query='{ __type(name:"PullRequest"){ fields{ name } } }'   # -> stack, stackEntry
gh api graphql -f query='{ __type(name:"PullRequestStack"){ name kind } }'   # -> OBJECT
```

## When to stack, and when not to

**Stack** when a change is genuinely layered and each layer stands on its own: a module extracted first and consumed second, an IAM role created before the workflow that assumes it, a schema migration under the code that reads it. The test is whether a reviewer can approve layer N without reading layer N+1.

**Do not stack** to split one coherent change into arbitrary commit-sized PRs. Every layer costs a full review (below), so a four-layer stack spends four reviews of someone else's time. If the layers are not independently reviewable, it is one PR.

**Cannot stack** across repositories. A two-repo change is still two coordinated PRs, and the manual restacking protocol in [`../examples/docs/git-worktree-and-squash-safety.md`](../examples/docs/git-worktree-and-squash-safety.md) still governs that case.

## What your rulesets add

### Branch naming applies to every layer

If a ruleset constrains branch names on all refs — a required ticket prefix, say — it applies to each layer branch too. `gh stack add -m "Fix login bug"` auto-generates a name like `03-24-fix_login_bug`, which such a ruleset **rejects on push**. Always pass the branch name explicitly:

```bash
gh stack add 1234-extract-auth-module      # correct
gh stack add -m "Extract auth module"      # auto-named, rejected at push time
```

### Each layer costs its own approval

GitHub enforces default-branch protection on **every** PR in a stack, including mid-stack ones that target another feature branch rather than the default branch. Under a ruleset requiring an approving code-owner review, four layers is four approvals, not one. Confirm the reviewer cost is acceptable before submitting.

### Unverified: auto-rebase vs `require_last_push_approval`

When a lower layer merges, GitHub rebases and retargets every layer above it server-side. If that rebase registers as a push by the PR author, `require_last_push_approval` may invalidate the approvals on all upper layers, forcing re-approval at every merge step.

**This has not been tested here.** Check it on the first stack that actually merges bottom-up, and record the answer.

### A ruleset bypass does not reach a stacked PR

Adding a user to a ruleset's bypass list grants merge rights on ordinary PRs and **not** on stacked ones. Every route out is closed at a different layer, so it presents as four unrelated problems rather than one:

| Route | What happens |
|---|---|
| `gh pr merge --admin` | refused — *"must be merged using the asynchronous merge REST API"* |
| GraphQL `mergePullRequest` | refused outright |
| `PUT /repos/{owner}/{repo}/pulls/{n}/merge-async` | accepted, returns `status: pending`, then never lands while an unbypassable rule stands |
| `gh stack merge` | see the guard note below — and it is the user's action regardless |

GitHub has this filed as an open bug: <https://github.com/orgs/community/discussions/204119>.

**The way out is to dissolve the stack, and the CLI cannot do it.** `gh stack unstack` silently no-ops — exit 0, no output, stack intact. The REST form works:

```bash
gh api -X POST repos/{owner}/{repo}/stacks/{n}/unstack    # -> 204, stack dissolved
```

Afterwards they are ordinary dependent PRs — each merges by its normal route, and their bases must be retargeted by hand in merge order.

**Decide this before `gh stack submit`.** If the base carries an approval ruleset the merger expects to bypass, that expectation does not survive stacking: either land the work as ordinary dependent PRs, or accept a real approval on every layer.

### `mergeStateStatus` is not evidence about what a given user may do

It is computed without regard to the viewer's bypass, so it reads `BLOCKED` for a user who can in fact merge. `viewerCanMergeAsAdmin` is the ruleset-aware field — it flips on a ruleset edit alone, with no branch-protection change involved.

**Read it through GraphQL, not `gh pr view --json`.** The field exists on the GraphQL `PullRequest` type but is not among the fields `gh pr view --json` exposes (checked on `gh` 2.99.0, where it errors with `Unknown JSON field`):

```bash
gh api graphql -f query='query($o:String!,$r:String!,$n:Int!){
  repository(owner:$o,name:$r){ pullRequest(number:$n){
    mergeStateStatus viewerCanMergeAsAdmin reviewDecision } } }' \
  -f o=<owner> -f r=<repo> -F n=<number>
```

A bypass entry must be added to **every** gating ruleset before that field flips; one ruleset short leaves it `false`.

## Worktree flow

A stack is N branches in one working copy, so it lives in a single worktree. `gh stack up`, `down`, `switch` and `checkout` run a branch switch between layers — safe inside a `/tmp` worktree, and a violation of the never-switch-in-a-repo-root rule if run in one.

```bash
git -C <repo> fetch origin
git -C <repo> worktree add /tmp/<slug> -b <ticket>-layer-1 --no-track origin/main
cd /tmp/<slug>
gh stack init <ticket>-layer-1
# ... work, commit ...
gh stack add <ticket>-layer-2
gh stack view            # confirm order and bases before submitting
gh stack submit
```

Run `gh stack sync` after any layer merges, and `gh stack view` before every submit.

## Guard coverage

The stack subcommands are separate verbs, so a guard keyed on `gh pr …` does not see them — coverage has to be added deliberately. The shipped [`destructive-guard`](../examples/hooks/destructive-guard/) covers them; the table below was verified by running that hook against each command:

| Command | Guard | Decision |
|---|---|---|
| `gh stack merge` | `destructive-guard` | **hard block, no approval path** |
| `gh stack submit` | `destructive-guard` | ask |
| `gh stack link` | `destructive-guard` | ask |
| `gh stack unstack` | `destructive-guard` | ask |
| `gh stack view/up/down/switch/checkout/sync` | — | silent, local-only |
| `gh api .../pulls/N/merge`, `.../merge-async` | `destructive-guard` | **hard block, no approval path** |
| `gh api .../pulls/N/merge-async/<id>` | — | allowed — read-only status poll, not a merge |

**[`pr-create-guard`](../examples/hooks/pr-create-guard/) covers `gh stack submit`.** It hard-blocks a submit from a dirty tree — where the layers would be missing the work you meant to include — and otherwise emits a stack-specific checklist, since a submit creates or updates every pull request in the stack rather than one. Verified by [`hook-tests/fixtures/pr-create-guard.tsv`](../examples/hook-tests/fixtures/pr-create-guard.tsv), whose two stack cases fail against the pre-coverage hook.

**`gh stack merge` is blocked harder than `gh pr merge`, not softer.** It lands the target layer *and every unmerged layer beneath it* in one operation, so the blast radius of a single mistaken call is the whole stack. There are three forbidden forms — `gh pr merge`, `gh api .../pulls/N/merge`, `gh stack merge` — and a guard message should name all three, or the reader who trips one retries with another.
