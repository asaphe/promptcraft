# Operational Safety Rules

- **Re-verify state after context continuation** — After any context continuation or session handoff, re-read actual files for: current git branch, terraform workspace, image tag, and target workflow. Never rely solely on continuation summaries for operational values.

- **Verify operational target at the start of each task** — When beginning work that targets an environment (kubectl, terraform, helm, aws), verify the active cluster, namespace, workspace, and directory before the first command. Re-verify after any context switch (different module, different environment, different cluster).

- **Checkpoint deep sessions proactively — and consider splitting at 100+** — At 50+ tool calls, offer a summary: current branch, what's done, what remains, and any open decisions. At 100+ tool calls, actively suggest splitting remaining work into a new session if there are distinct remaining tasks — correction rates double in long sessions due to context drift.

- **Plan mode rejections mean the plan isn't ready** — When ExitPlanMode is rejected, ask what's missing. Don't try to exit again without addressing feedback. Present plans incrementally.

- **Enumerate before destructive operations** — When asked to "remove" or "clean up," produce an explicit numbered list of exactly which resources will be affected. Get per-item or per-batch confirmation. Never infer scope from broad terms. When a pattern or wildcard is involved (e.g., "destroy everything with clickhouse in the name"), group matches by category (namespaces vs services vs databases vs secrets) and get per-group confirmation — a pattern like `*clickhouse*` can match far more resource types than intended.

- **Read before editing — no parallel edits without reads** — Never issue an Edit call for a file not read in the current turn. When editing multiple files, read them all first, then edit. After context continuations, re-read before editing.

- **Cross-reference all variants before copying** — When duplicating or adapting files that exist in multiple variants (e.g., stg/prod, sibling modules, parallel configs), never blindly copy from a single source. Diff all available variants against each other first and identify discrepancies. But a difference between variants is not automatically a bug — it may be intentional, or it may be dead code. For each discrepancy, **verify whether it has any effect** by tracing how the value is actually used (read the consuming template/code, check the deployed state). Only adopt a change from another variant after confirming it matters.

- **Copy files with file operations, not via content relay** — When duplicating files, use direct file reads and writes (Read -> Write, or `cp` + targeted edits). Do not relay file contents through an intermediary agent or summary — inline comments, whitespace, and subtle formatting get silently stripped, causing cosmetic drift that obscures real diffs later.

- **Fix diagnostics immediately — never rationalize them away** — When IDE diagnostics or linter warnings appear after a change (e.g., `<new-diagnostics>` in tool output), fix them in the same session before moving on. Do not classify warnings as "minor", "style-only", or "won't affect rendering" to avoid fixing them. Every diagnostic is a finding. If it can't be fixed right now, flag it explicitly to the user — do not silently skip it.

- **Reference docs are not inventories** — Never assert an AWS resource (permission set, role, secret, security group, etc.) doesn't exist based solely on reference docs or cached knowledge. Always verify against the actual AWS service (`sso-admin list-permission-sets`, `secretsmanager list-secrets`, `iam list-roles`, etc.) before claiming something is missing or invalid.

- **Investigation is not implementation — present findings first** — When asked to investigate, verify, or analyze something: (1) classify the error signature before theorizing — EOF/timeout = transient, 403/denied = access, connection refused = network; (2) if the failure could be transient, recommend a re-run before deep investigation; (3) present findings and get confirmation before creating branches, editing files, or proposing changes — investigation tasks are not implementation tasks unless the user says so; (4) configuration differences found during investigation are findings to report, not automatic root causes — correlation is not causation. This applies to all investigation tasks, not just failure analysis.

- **"Verified" means show your work** — When claiming something is verified, include the actual commands run and their output or a link to a passing CI run. Never use "verified" as a bare status word. If the user asks "did you verify?" it means the previous answer was insufficient — provide concrete evidence, don't just repeat the claim.

- **Never block the user on long-running tasks** — CI polling, `terraform plan/apply`, large test suites, and similar long-running operations must run in the background (`run_in_background: true`) or be delegated to a subagent. Never hold the main conversation waiting on a command that may take more than ~30 seconds.

- **Parallel Terraform operations require isolated directories** — Terraform's `.terraform` directory stores the selected workspace and provider state locally. To plan or apply multiple workspaces of the same module in parallel, create isolated copies (e.g., `cp -r` to `/tmp/tf-{module}-{workspace}`) and run `terraform init` + `workspace select` independently in each. Never switch workspaces in the same directory from parallel processes.

- **Prefer dynamic resolution over static config** — Use runtime APIs, naming conventions, or data source queries over static mapping files or boolean flags that go stale silently. When the question is "does resource X exist?", query for it at runtime rather than maintaining a flag that says it should. Static flags create mismatch risk between the system that provisions and the system that consumes. Example: querying AWS Secrets Manager for secret existence instead of maintaining an `enabled` boolean that must stay in sync across Terraform modules and CI workflows.

- **Don't hardcode a list of names when the list is dynamic** — When generating config, Terraform, or code that references a set of entities (tenants, apps, teams, environments), never enumerate them as a hardcoded list unless the list is explicitly known to be exhaustive and static. Instead, derive from a single authoritative source (tfvars, database, API response). Hardcoded lists go stale silently.

- **Accept the user's diagnosis — don't re-investigate confirmed causes** — When the user says "the issue is X" or "that's because of Y", treat it as ground truth and act on it. Do not repeat debugging steps, re-examine logs, or challenge the diagnosis with alternative theories. Re-investigation after user confirmation wastes time and signals distrust.

- **Never infer API field names from convention — look up the schema** — Do not guess that a field is named `id`, `task_id`, `custom_id`, or similar based on naming patterns. Always fetch the actual API response or schema documentation to confirm the exact field name. Convention-based guesses introduce silent bugs when the API uses a non-obvious name.

- **Re-examine prior assessments when the user challenges them** — When the user says "I think we were wrong" or "verify whether this was actually an issue", treat it as a signal to actively re-check — not to defend the original conclusion. Re-read the relevant code, re-run commands, and report what you find. A challenge is not an insult; it's a request for evidence.

- **Verify before proposing — docs, tests, and artifacts may already exist** — Before suggesting that documentation, tests, or configuration be added, check whether they already exist in the codebase. Proposing work that is already done wastes the reviewer's time and signals insufficient codebase familiarity. Use Glob/Grep to confirm absence before recommending additions.

- **Ask about VPN before attempting workarounds** — When encountering connectivity or network errors to internal resources (EKS, internal APIs, private endpoints), ask the user if their VPN is connected before trying alternative approaches. A missing VPN connection is the most common cause of internal connectivity failures.

- **Resolve actual versions and tags before using them** — Never assume a version, image tag, Helm chart version, or Terraform provider version. Always query the source of truth first: `aws ecr describe-images` for container tags, `helm search repo` for chart versions, `terraform providers lock` for provider versions.

- **Verify paths and names exist before referencing them** — Before writing imports, file references, module sources, or resource names, verify they exist with Glob/Grep/ls. Do not construct paths from memory or convention.

- **Plan multi-workspace Terraform operations upfront** — Before running `terraform plan` across multiple workspaces of the same module, list all target workspaces once, then plan each sequentially or in parallel (using isolated directories per the existing rule). Batch all plans first, review the full set, then apply — do not interleave plan->review->apply per workspace.

- **Cache fetched credentials and secrets within a session** — When a secret or token is fetched (`aws secretsmanager get-secret-value`, OIDC token exchange, etc.), export it to an env var on first fetch (e.g., `export MY_TOKEN=$(aws secretsmanager get-secret-value ...)`). Reuse `$MY_TOKEN` in subsequent calls. Env vars die with the shell session — no cleanup needed and no secrets left on disk.

- **Use `kubectl rollout status` or `kubectl wait` instead of polling** — When watching a deployment rollout or waiting for a resource to become ready, use blocking commands (`kubectl rollout status deployment/<name> -n <ns> --timeout=300s` or `kubectl wait --for=condition=Ready pod -l app=<name> -n <ns> --timeout=300s`) instead of repeatedly running `kubectl get pods`. Run blocking waits with `run_in_background`.

- **Fetch `terraform workspace list` once per module per session** — Save the output to a temp file on first call. Do not re-run `workspace list` when iterating over workspaces in the same module. Invalidate the cache (re-fetch) after any workspace mutation (`workspace new`, `workspace delete`, or `-or-create` patterns) since those change the list.

- **Use `nslookup` or `dig` for DNS verification, not application-level resolution** — Python's `socket.getaddrinfo`, `curl`, and most applications resolve through `/etc/hosts` first, which can mask DNS issues. `nslookup` and `dig` query DNS directly, bypassing `/etc/hosts`. When debugging connectivity where DNS is suspect, always use `nslookup`/`dig` for ground truth, then check `/etc/hosts` for overrides.
