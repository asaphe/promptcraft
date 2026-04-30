# GitHub Actions Workflow Authoring

Patterns and gotchas for authoring `.github/workflows/*.yaml` and reusable / composite actions. Apply before committing any workflow change.

## Triggers & Path Filtering

- **New workflows can't be dispatch-tested from a PR branch** — `workflow_dispatch` only works on the default branch (404 otherwise). To exercise a new workflow's `pull_request` path, add a temporary file matching the path filter (remove before merge).
- **Only `push`, `pull_request`, and `pull_request_target` support `paths` filtering** — All other event types fire repo-wide and silently ignore `paths` / `paths-ignore`.
- **`on.push.paths` misses services when PRs merge in quick succession** — GitHub coalesces rapid push events and evaluates paths on the tip commit's diff only. For workflows where every merge matters (container builds, etc.), remove `paths` from `push` and use `dorny/paths-filter` inside the job.
- **Push-trigger path patterns must match the actual workflow filename** — Hyphens vs underscores matter. A mismatch causes the trigger to silently never fire.
- **`persist-credentials: false` + shallow clone breaks `dorny/paths-filter` on push-triggered workflows — pair with `fetch-depth: 0`** — When `persist-credentials: false` is set, the git credential helper is stripped after checkout. On push-triggered workflows, `dorny/paths-filter` must compare against the `before` SHA; if that commit isn't in the shallow clone it falls back to `git fetch --depth=1 --no-tags origin <sha>`; without credentials that fetch fails with `fatal: could not read Username`. Fix: add `fetch-depth: 0` to the same checkout step so all history is fetched upfront. Apply the same fix to PR-triggered workflows using this action as a precaution. Do **not** remove `persist-credentials: false` on `pull_request` / `pull_request_target` workflows that check out PR-head code — the checked-out code runs with access to the credential store.

## Inputs & Expressions

- **GHA omits env vars when step output expressions are empty** — `${{ steps.X.outputs.Y }}` renders to nothing (not empty string) if the output doesn't exist. With `set -u` the script exits silently. Use `${VAR:-default}` for all env vars sourced from step outputs or dispatch inputs.
- **`gh workflow run` sends boolean inputs as actual booleans** — Comparing with `== 'true'` (string) always evaluates to false. Use `== true` (unquoted) in job conditions with `inputs.*` context. (`github.event.inputs.*` always delivers strings.)
- **Test jq scoping in nested `any()` locally** — jq 1.8+ changed variable scoping inside nested `any()` generators: bare `.` resolves to the outer binding. Use explicit `as $var` bindings or test locally before committing.

## Version Pinning

- **Check the repo for standard pinned versions before selecting** — Search `grep -r "uses: <action-name>" .github/` and use the same pinned commit SHA. Never use floating tags (`@latest`, `@v1`, `@main`) for third-party actions.
- **Verify against the action's release history before committing** — Check the action's GitHub releases page to confirm the version exists and is the latest stable release. Dereference annotated tags (`gh api repos/{owner}/{repo}/tags --paginate --jq ...`) — `git/ref/tags/{name}` returns the tag object SHA, not the commit SHA actions pin to.

## Linters & Pre-commit

- **Run `actionlint` before committing workflow changes** — Use a pre-commit hook that blocks `git commit` when staged workflows fail actionlint. Catches syntax errors (including `environment:` on `uses:` jobs) before the PR exists. Config: `actionlint -config-file .github/actionlint.yaml`.
- **Run `zizmor` before committing workflow changes** — Catches GHA security findings (unpinned refs, template injection, excessive permissions, credential-persisting checkouts) before CI blocks the PR. Local: `zizmor .github/workflows/<file>.yaml --min-severity=high --offline`. CI gate is `--min-severity=high`; only `high`+ findings block merge. For intentional exceptions, add inline `# zizmor: ignore[<audit-id>]` with a justification comment. Scoped policies (internal reusables `@main`-pin, third-party actions must SHA-pin) live in `.github/zizmor.yml`.
- **actionlint Enterprise runner labels** — Enterprise managed runners (e.g., `ubuntu-latest-m`) are org-scoped and absent from actionlint's built-in catalog. Add to `.github/actionlint.yaml` under `self-hosted-runner.labels`.

## Runner & Check Hygiene

- **`gh pr checks` renders cancelled as "fail"** — To distinguish real failures from cancellations, query the API: `gh api repos/{org}/{repo}/actions/runs/{id}/jobs --jq '.jobs[] | {name, conclusion}'`.
- **`gh run delete` removes the UI entry but doesn't stop the runner** — Cancel the run first (`gh run cancel`) before deleting to avoid state locks from the still-executing process.
- **CI check name changes AND removals must update the branch ruleset** — When renaming, replacing, or removing a required check job, update `required_status_checks` in the same PR. A removed job left in the ruleset shows "Expected — Waiting for status to be reported" permanently and blocks merge. Verify with `gh api repos/{org}/{repo}/rulesets/{id}`.

## Filename & Identifier Conventions

- **Workflow filenames: pick a convention and stick to it** — One common shape is `{domain}-{action}.yaml` with hyphens, but the filename style is opinion. The `.yaml` vs `.yml` extension and the consistency between filename and the `name:` field are the load-bearing parts.
- **Step / job IDs must avoid hyphens (real mechanic)** — GitHub expressions treat `-` as minus. `steps.foo-bar.outputs.x` is parsed as `steps.foo - bar.outputs.x` (subtraction). Use `[a-zA-Z0-9_]` only. `snake_case` vs `camelCase` is style; the no-hyphens rule is mechanically enforced.

## Workflow Rename Protocol

- **Never use naive global string replace for renames** — Replacing a base name globally also corrupts longer names that share the prefix (e.g., replacing `clickhouse_config` globally also rewrites `mt_clickhouse_config`). Use exact-match replacement (full filename including extension) or context-aware scripts. Verify every changed file after bulk operations.
- **Grep the FULL reference surface before renaming** — Workflow filenames appear in: workflow `uses:` refs, `on.push.paths` self-triggers, CODEOWNERS, `gh api` dispatch paths in scripts, IAM `job_workflow_ref` trust policies, agent definitions, docs, READMEs, skills, rules, and cross-repo references. A rename is not complete until all of these are updated.
- **Disable stale workflow entries after rename** — GitHub keeps old workflow entries active in the UI after a file rename. They accumulate runs and confuse the Actions tab. After merging a rename PR, disable stale entries: `gh api repos/{owner}/{repo}/actions/workflows/{id}/disable -X PUT`.

## Shell Scripting in Workflow Steps

- **Use `jq -cn --arg` / `--argjson` for JSON construction — never string interpolation** — Shell string interpolation breaks on special characters (quotes, newlines, backslashes) and creates injection risk. Use `--arg` for string values and `--argjson` for any non-string JSON value (booleans, numbers, arrays, objects). `--arg` always produces a quoted string — using it for a boolean produces `{"enabled":"true"}` (string) instead of `{"enabled":true}` (boolean), causing silent type errors in API consumers.
- **GHA strips `run:` block indentation** — YAML multiline scalar indentation is removed down to the `run:` key's level before the script runs. Heredoc delimiters inside `run:` blocks appear at column 0 in the actual shell script — don't add extra leading spaces expecting them to be preserved.

## Cross-Repo Reusable Workflows

- **`actions/checkout` in reusable workflows defaults to the caller repo** — When reviewing reusable-workflow PRs, verify every `path: <prefix>` checkout that should target the reusable repo has `repository: <your-org>/<reusable-workflows-repo>`. Without it, the directory gets a copy of the caller, not the reusable repo.
- **Composite action `uses:` resolves from workspace root** — A composite action invoked via `./<prefix>/.github/actions/X` has its internal `uses: ./.github/actions/Y` resolved from the workspace root (caller checkout). If `Y` was migrated to the reusable repo, it must be `./<prefix>/.github/actions/Y`.
- **After action migration, audit the full chain** — Check: (1) all `path: <prefix>` checkouts have `repository:`, (2) all `./.github/actions/*` refs in reusable composite actions still exist in the caller, (3) if not, they need the `./<prefix>/` prefix.

## OIDC IAM Trust

- **`environment:` is not valid on `uses:` (reusable caller) jobs** — Only jobs with `steps:` accept `environment:`. A caller job that uses `uses:` cannot declare `environment:` — actionlint rejects it with `[syntax-check]`. When an OIDC `sub` claim fix requires an environment declaration, the fix must go on the job inside the reusable workflow that actually mints the token (the job with `steps:` and the `configure-aws-credentials` action), not on the thin caller job.
- **AWS requires `sub` on every OIDC trust statement** — Even when using `job_workflow_ref`, the trust policy must include a `StringLike` condition on `token.actions.githubusercontent.com:sub`. Without it, AWS returns `MalformedPolicyDocument`. Use `repo:<your-org>/*` as the broad `sub` alongside a specific `job_workflow_ref`.
- **`job_workflow_ref` works for ALL workflows, not just reusable** — For local workflows, it reflects the workflow file itself. This enables per-workflow IAM roles with least-privilege permissions.
- **`job_workflow_ref` includes the branch ref — can't test from feature branches** — A feature branch run produces `...@refs/heads/dev-xxx`, which won't match a `@refs/heads/main` trust condition. To test: temporarily add the branch ref to the trust policy AND the GitHub environment branch policy, test, then revert both before merging.

## Hotfix Tag Boundary

- **Tags run workflow code from the tagged commit — old commits may use a deprecated IAM role** — When a tag is pushed, GitHub uses the `.github/workflows/` files at that commit's tree. If the IAM trust policy was tightened later (e.g., requiring `job_workflow_ref` from a specific reusable repo), commits before that change still call old workflows whose role assumption now fails with "Not authorized to perform sts:AssumeRoleWithWebIdentity".
- **Fix: cherry-pick app commits onto a recent `main` base, retag** — Identify the app-only commits in the hotfix series (`git log <base-tag>..<failing-tag> --oneline`), create a new branch from recent `main`, cherry-pick those commits, then tag from the new HEAD. Do not include old `.github/` or workflow file commits in the cherry-pick — the new base already has correct workflow code.
- **Never work around this with trust policy changes** — The lockdown is correct. The fix is always a rebase.
