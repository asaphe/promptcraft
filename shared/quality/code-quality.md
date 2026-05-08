# Code Quality & Linting

> **Scope:** Universal — applies to any AI coding assistant on any project. Adapt examples to your environment.

Code is presented only after it passes its language's lint+format gate. "Works on my machine" is not a quality bar — the lint pass is.

## Lint gates by language

| Language | Required gate |
|----------|---------------|
| Shell | `shellcheck` (zero errors) |
| Dockerfile | `hadolint` (zero errors) |
| Python | `ruff` lint + format |
| Markdown | `markdownlint` against the project's config |
| YAML | parses cleanly; `yamllint` if the project uses it |
| TypeScript / JavaScript | project's ESLint config |
| Terraform | `terraform fmt -check` + `tflint` |

When a project pins different tools or extra steps (e.g., `mypy`, `prettier`, `checkov`), discover them via the project's `package.json` / `pyproject.toml` / CI config and run them too. The lint gate is whatever CI enforces, not a generic default.

## Workflow

1. Write the code.
2. Run the relevant linter(s).
3. Fix every reported issue.
4. Present the final, lint-passing version — show the command output, not a claim.

If you can't run the linter (sandbox limitation, missing tooling), say so explicitly and provide the exact command for the user to run.

## Lint-disable / suppress comments

Treat `// eslint-disable`, `# noqa`, `# type: ignore`, `// @ts-ignore`, `tflint-ignore` as code smells:

- **Default: don't.** A lint warning usually points at a real problem; suppressing is rarely the right fix.
- **Justify in writing.** If suppression is correct (e.g., generated code, intentional pattern), the comment must include the *reason* — not just "ignore this".
- **Scope tightly.** Suppress one rule, one line. Never blanket-disable a file.

When the suppressed pattern appears repeatedly, that's a signal to update the lint config (or the rule) — not to scatter more suppressions.

## Style vs correctness

A linter enforces style; correctness is a separate gate. Even with a clean lint pass, ask:

- Does it handle the failure modes (network errors, empty inputs, oversized inputs, concurrent access)?
- Does it match project conventions visible in surrounding code?
- Does it preserve the invariants the calling code depends on?

Lint passing is necessary, not sufficient.

## Deviating from defaults

Sometimes the right code violates a default lint rule. When deviating:

1. State the standard approach.
2. State why this case is different.
3. Show how the alternative still meets the quality bar.
4. Suppress with a tight `// eslint-disable-next-line <rule>` (or equivalent) and a one-line reason.

Innovation in logic or design is fine; ignoring lint errors is not the right venue for it.

## Security floor

Independent of any other rule, every contribution must:

- **Never hardcode secrets** — no API keys, tokens, passwords, account IDs in code, configs, or container images. Use the project's secret-injection mechanism.
- **Use least privilege** — IAM policies, K8s RBAC, file permissions, env-var scope all default to the minimum required.
- **Validate at trust boundaries** — user input, external API responses, untrusted config. Don't validate at internal boundaries that already have typed contracts.
- **Mask sensitive values in logs** — secrets, PII, tokens. CI output is shared state; treat it as semi-public.
- **Pin dependencies** — base images, package versions, action SHAs. `latest` is a supply-chain liability.

These are non-negotiable; lint gates won't catch them but they fail the same gate (don't ship).

## See also

- [`documentation.md`](documentation.md) — documentation quality standards.
- [`research-standards.md`](research-standards.md) — when to research vs. when to act.
- [`../principles/development-principles.md`](../principles/development-principles.md) — verification and impact analysis.
- [`../principles/tool-safety.md`](../principles/tool-safety.md) — destructive commands, approval gates.
