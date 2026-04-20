---
paths:
  - ".github/**"
---
# CI Runner Rules

- **Unknown actionlint runner label — verify before proposing a fix** — When actionlint flags an unknown `runs-on` label with `[runner-label]`, do NOT assume the label is wrong or suggest changing it. Investigation order: (1) check the org's registered runners (`gh api repos/{owner}/{repo}/actions/runners` or GitHub Settings -> Actions -> Runners); (2) check GitHub docs for standard labels. If the runner is a valid Enterprise managed runner, the fix is to add the label to `.github/actionlint.yaml` under `self-hosted-runner.labels`, not to change the workflow.

- **GitHub Enterprise managed runners require explicit actionlint registration** — GitHub Enterprise "Default Larger Runners" (e.g., `ubuntu-latest-m`) are org-scoped and absent from actionlint's built-in GitHub-hosted label catalog. Any such label must be added to `.github/actionlint.yaml` under `self-hosted-runner.labels`. Current registered Enterprise labels: `ubuntu-latest-m`.

- **Failing CI checks are never dismissible as pre-existing** — A failing check on `main` or on a PR blocks everyone and must be fully investigated regardless of which commit introduced it. Never write off a check failure as "not caused by our changes" — determine the root cause, the correct fix, and include it in the current PR if it applies.

- **`gh pr checks` renders cancelled as "fail"** — The `gh pr checks` CLI shows cancelled jobs as `fail`. To distinguish real failures from cancellations, query the API: `gh api repos/{owner}/{repo}/actions/runs/{id}/jobs --jq '.jobs[] | {name, conclusion}'`. A `cancelled` conclusion typically indicates concurrency conflicts or workflow-level cancellation rather than a code issue — but still investigate to confirm the cause.

- **`gh workflow run` sends boolean inputs as actual booleans** — When a workflow uses `on.workflow_dispatch.inputs` with `type: boolean`, `gh workflow run -f flag=true` sends a real boolean. Comparing with `== 'true'` (string) always evaluates to false and silently skips the job. Use `== true` (unquoted) in job conditions when using the `inputs.*` context. Note: `github.event.inputs.*` always delivers strings — this only applies to the newer `inputs.*` context.

- **Push-trigger path patterns must match the actual workflow filename** — When adding `on.push.paths` to a workflow, confirm that any `**/{name}.yml` pattern exactly matches the real filename (hyphens vs underscores matter). A mismatch causes the trigger to silently never fire.

- **Test jq scoping in nested `any()` locally** — jq 1.8+ changed how variable scoping works inside nested `any()` generators: bare `.` inside an inner `any()` resolves to the outer binding instead of the inner generator. This can cause unintended matches (e.g., "build all container services on every PR"). Test complex jq expressions locally (`jq -n '...' <<< '{...}'`) before committing, or use explicit `as $var` bindings to lock variable scope in nested generators.
