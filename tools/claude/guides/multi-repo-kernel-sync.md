# Multi-Repo Kernel Sync

How to distribute shared AI-assistant rules across multiple repositories using a synced kernel + local overlay pattern, with CI-driven propagation and drift detection.

## The Problem

Once an organization runs Claude Code across several repositories, the same behavioral rules (git discipline, PR standards, review methodology) need to exist in each repo's `.claude/` directory — rules only load from the repo you're working in. The naive approaches both fail:

- **Copy-paste** drifts immediately. Someone fixes a rule in one repo; three months later the other repos still enforce the stale version, and nobody notices because drift is invisible until it bites.
- **Git submodules** technically solve drift but add friction everywhere: every consumer needs a pointer-bump PR per change, clones need `--recurse-submodules`, and reviewers see an opaque SHA change instead of the actual rule diff.

The kernel pattern gets single-source-of-truth without either cost: files are plain committed content in every repo (reviewable diffs, zero clone friction), and a CI workflow keeps them identical.

## Two File Families

| Family | Filename pattern | Role |
|--------|-----------------|------|
| **Kernel** | `<topic>-shared.md` | Single source of truth. Byte-identical across all repos. Edited only in the source repo. |
| **Overlay** | `<topic>.md` sibling | Per-repo extensions. Repo-local, never synced. |

Both load additively into the assistant's context — a kernel + overlay pair contributes both files. Overlays may be absent when the kernel fully covers the topic.

The `-shared` suffix is load-bearing: it marks a file as synced (don't edit here, edit in the source repo) and gives the sync workflow an unambiguous glob to operate on. Anyone opening the file can tell from the name alone whether their edit will survive.

**Exception — agent definitions:** Claude Code identifies agents by exact filename, so a synced agent file cannot take the `-shared` suffix (it would change the agent's identity). Sync those by explicit filename instead of glob, and note the exception in the kernel governance doc.

Typical kernel locations:

| Path | Glob | Content |
|------|------|---------|
| `.claude/rules/general/` | `*-shared.md` | Cross-repo behavioral rules |
| `.claude/docs/` | `*-shared.md` | Shared methodology + kernel governance docs |
| `.claude/agents/` | explicit filenames | Shared agents (see exception above) |

## Kernel, Overlay, or Repo-Local?

When adding a new rule or doc:

| Scenario | Place |
|----------|-------|
| All repos need it identically | Kernel — `*-shared.md`, synced |
| Most repos identical, one extends | Kernel + overlay in the extending repo |
| Each repo has its own version | Repo-local only |
| Domain-specific (one repo's tech stack) | Repo-local only |

The most common mistake is putting repo-specific content in a kernel — it then loads into sessions working on unrelated repos, wasting context tokens on irrelevant rules. The second most common is putting shared content in an overlay, which recreates the copy-paste drift the pattern exists to prevent.

## Edit Workflow

1. **Edit in the source repo only.** Kernel edits in consumer repos are overwritten by the next sync — the naming convention is the reminder.
2. **Merge to main.** The sync workflow fires on push-to-main touching kernel paths.
3. **Nothing else.** The workflow opens sync PRs in each consumer repo as a bot, with auto-merge enabled. Once consumer CI is green, the PRs merge themselves (the bot needs a bypass exemption on each consumer's required-review ruleset).

Overlays need no workflow — edit them in place in their one repo.

## The Sync Workflow

The caller in the source repo is small — path-triggered, delegating to a reusable workflow:

```yaml
name: Kernel sync

on:
  workflow_dispatch: {}
  push:
    branches: [main]
    paths:
      - '.claude/docs/*-shared.md'
      - '.claude/rules/general/*-shared.md'

permissions:
  contents: read

concurrency:
  group: kernel-sync
  cancel-in-progress: false

jobs:
  sync:
    # Skip when the triggering commit is itself a sync merge —
    # breaks the re-fan cascade (see below).
    if: ${{ github.event_name == 'workflow_dispatch' || !startsWith(github.event.head_commit.message, 'chore(kernel)') }}
    uses: <org>/<workflows-repo>/.github/workflows/kernel-auto-sync.yaml@main
    secrets:
      AUTOMATION_APP_CLIENT_ID: ${{ secrets.AUTOMATION_APP_CLIENT_ID }}
      AUTOMATION_APP_PRIVATE_KEY: ${{ secrets.AUTOMATION_APP_PRIVATE_KEY }}
```

The reusable workflow does the fan-out:

```yaml
name: Kernel auto-sync

on:
  workflow_call:
    secrets:
      AUTOMATION_APP_CLIENT_ID: { required: true }
      AUTOMATION_APP_PRIVATE_KEY: { required: true }

permissions:
  contents: read

jobs:
  sync:
    runs-on: ubuntu-latest
    timeout-minutes: 10
    steps:
      - uses: actions/checkout@<pinned-sha>
        with:
          ref: ${{ github.sha }}
          persist-credentials: false

      # GitHub App token scoped to exactly the repos being synced.
      # The default GITHUB_TOKEN cannot push branches or open PRs
      # in other repositories.
      - id: app_token
        uses: actions/create-github-app-token@<pinned-sha>
        with:
          client-id: ${{ secrets.AUTOMATION_APP_CLIENT_ID }}
          private-key: ${{ secrets.AUTOMATION_APP_PRIVATE_KEY }}
          owner: <org>
          repositories: <source-repo>,<consumer-repo-1>,<consumer-repo-2>

      # For each consumer: clone, copy kernel files, diff;
      # if changed, push a branch and open a PR with auto-merge enabled.
      # Identical content = no PR (idempotent re-runs are no-ops).
      - name: Fan out sync PRs
        env:
          GH_TOKEN: ${{ steps.app_token.outputs.token }}
        run: ./scripts/kernel-sync.sh "${{ github.event.repository.name }}" "${{ github.sha }}"
```

Design points that aren't obvious until they fail:

- **The cascade skip-condition is mandatory.** A sync PR merging in a consumer repo is itself a push-to-main touching kernel paths. If that consumer also runs the caller workflow (symmetric setups where multiple repos may author kernels), the merge re-triggers sync, which opens PRs back at the other repos, which merge and re-trigger again. Gate on the sync commit-message prefix to break the loop. Keep `workflow_dispatch` exempt from the gate so manual re-runs always work.
- **`concurrency` without `cancel-in-progress`.** Two kernel merges in quick succession should queue, not race — a cancelled half-fan-out leaves some consumers synced and others not, which is exactly the partial-drift state the system exists to prevent.
- **Diff before opening a PR.** The sync script should compare content and skip consumers that already match. This makes re-runs free and keeps the PR queue clean.
- **Receive-only consumers are valid.** A repo can receive kernel updates without ever authoring them — it simply has no caller workflow. Useful for low-traffic repos where nobody should be editing shared rules anyway.

## Drift Detection as a Backstop

Auto-sync fails silently in predictable ways: app token expiry, a consumer's CI outage blocking auto-merge, a ruleset change revoking the bot's bypass. A scheduled drift detector catches all of them with one mechanism — hash-compare kernel files across every repo's main and alert on divergence:

```yaml
on:
  schedule:
    - cron: '0 9 * * *'

# For each kernel file: fetch from every repo's main via the API,
# md5sum, compare. Divergence -> post file list + repos to a chat channel.
```

This is deliberately dumb. It doesn't know *why* drift happened — it just guarantees drift is visible within a day instead of whenever someone happens to notice a rule behaving differently across repos.

## Manual Fallback

Keep a local sync skill (or script) that copies kernel files between checkouts and opens PRs — but treat it strictly as a fallback for when CI can't run: the workflow is broken, or a kernel change is being driven from a repo without a caller workflow. In the normal flow (edit, merge to main), the automation handles propagation; PR checklists should say "sync workflow auto-handles propagation," not instruct people to run the manual skill. A manual step that usually isn't needed will sometimes be run redundantly and sometimes skipped when it *was* needed — automation plus a drift backstop beats human memory.

## Common Pitfalls

- **Editing a kernel file in a consumer repo** — the edit merges, then the next sync PR reverts it. The `-shared` naming convention is the guard; reviewers should reject kernel-file diffs outside the source repo.
- **Editing a kernel locally without merging** — sync fires on push to main; uncommitted or unmerged edits propagate nowhere.
- **Forgetting new kernel paths in the workflow globs** — a new kernel directory that isn't in the caller's `paths:` filter and the sync script's target list silently never syncs. Add the path in both places and document it in the governance doc.

## Related Guides

- [Global CLAUDE.md Guide](global-claude-md-guide.md) — the personal cross-project layer; kernels are its team-level analog
- [Learning System Guide — Plugin Distribution](learning-system-guide.md#plugin-distribution) — plugin packaging as an alternative distribution mechanism for hooks/skills/agents (kernels suit rules and docs that must be reviewable in-repo)
- [GitHub Actions Integration](github-actions-integration.md) — running Claude Code itself inside CI
