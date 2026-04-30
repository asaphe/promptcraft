# Terraform Module Structure Rules

Authoring rules for reusable Terraform modules. Every rule below is checkable in PR review.

- **All data sources belong in `data.tf`** — Never place `data` blocks inline in `main.tf` or other resource files. When reviewing, search each `.tf` file for `data "` blocks outside `data.tf` and flag them.

- **Every variable needs `type` and `description`** — Variables without `type` default to `string`, hiding the actual contract. Variables without `description` are opaque to consumers. Both are mandatory.

- **Every output needs `description`** — Outputs are the module's public API. Undescribed outputs force consumers to read source code to understand what they're getting.

- **Every module must have a `README.md`** — The README is the entry point for any developer consuming the module. It must include: what the module does, basic usage example, and any non-obvious behavior. Missing README is a critical finding.

- **No hardcoded environment-specific values** — Account IDs, ARNs, region-specific endpoints, and environment names must be variables or data sources, never defaults or literals. The module must work across environments without code changes.

- **Use `this` for the primary resource** — When a module has one main resource, name it `this` (e.g., `resource "aws_s3_bucket" "this"`). Secondary resources get descriptive names. This convention makes module code scannable.

- **Provider pinning policy in modules — pick one and apply it consistently** — Two valid approaches: (a) HashiCorp's recommended pattern: every module declares `required_providers` for every provider it uses (HashiCorp and third-party), in `versions.tf`; (b) the "thin module" pattern: `versions.tf` exists only when the module uses non-HashiCorp providers (Databricks, Datadog, ClickHouse, etc.) and HashiCorp provider versions are owned by the root config. The HashiCorp pattern is the more portable default; the thin-module pattern reduces version churn across many modules consuming the same root. The wrong shape is **mixing both** in the same library.

- **Modules must not define `backend` or `provider` blocks** — Reusable modules inherit their provider configuration from the calling root module. A `backend.tf` or `providers.tf` in a module is a structural error — it prevents composition.

- **`lifecycle { prevent_destroy = true }` on stateful resources** — Databases, secrets, storage credentials, catalogs, and S3 data buckets must have `prevent_destroy` to guard against accidental deletion via `terraform destroy` or misconfigured plans.
