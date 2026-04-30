# Datadog Config & Provider Gotchas

Authoring rules and provider-specific gotchas for Datadog configurations managed via Terraform (and the Datadog provider). Most are silent failures — Datadog accepts the wrong shape and produces empty charts, broken on-call coverage, or privilege-escalated keys without surfacing an error.

## On-call schedules

- **Users in on-call schedules must be active Datadog accounts.** SCIM-managed deprovisioning removes Datadog user accounts when someone leaves, but does not update on-call schedules referencing them. CI should validate all on-call users against the Datadog API alongside `terraform plan`. To manually check user status: `pup users list --agent`.

- **`custom` rotation layers without `restriction` apply 24/7.** Weekday / weekend splits require explicit `restriction` blocks with `start_day`, `start_time`, `end_day`, `end_time`. Missing restrictions cause unexpected coverage gaps — the schedule is technically correct, just not what was intended.

## Workspace ↔ JSON config conventions (only if you use the `vars/{team}.json` pattern)

> Skip this section if you don't use a `terraform.workspace` + `vars/*.json` config-driven pattern. Many Datadog-as-code repos use Pulumi, CDK, or a different file convention.

- **Workspace name must match the JSON filename prefix.** When using `terraform.workspace` to select config files, two common patterns:
  - **Single file per team** (indexes, on-calls): `vars/{team}.json` → workspace `{team}`
  - **Multiple files per team** (monitors, dashboards): `vars/{team}-{name}.json` → workspace `{team}`. The `{team}-*` glob selects all files for that workspace.

- **New teams must be added to the workflow matrix.** When adding a `vars/{team}.json` file, also add the team name to the `team` input choices in your dispatch workflow. Without this, `workflow_dispatch` manual runs can't target the new team.

## Module defaults vs effective defaults

- **README field docs must match the calling code, not the module defaults.** Each `main.tf` overrides module defaults via `try(each.value.field, <override>)`. The user-facing default is the value in the calling code, not the module's `variables.tf`. Always verify defaults by reading the `try()` fallbacks in the calling code. Examples of past drift: warning threshold documented as 95 when code used 90, priority direction documented backwards, required fields documented as optional.

## Log widget facets

- **`group_by` facets: tags use bare names, attributes use `@` prefix.** In log-based timeseries / toplist widgets, `group_by[].facet` must be `"kube_namespace"` (not `"@kube_namespace"`) for infrastructure tags. Only log *attributes* use the `@` prefix (e.g., `"@http.status_code"`). Using `@` on a tag produces empty charts with no error.

## Metric semantics

- **`kubernetes.containers.restarts` is a lifetime cumulative gauge.** `.as_count()` is a no-op on gauges. Widget titles like "Total Restarts (24h)" are misleading — the value reflects the container's entire lifetime, not the dashboard time range. Only add a time-window label if the widget has an explicit `time.live_span` lock.

## Provider gotcha — `datadog_application_key` privilege escalation

`datadog_application_key` silently creates a key owned by the Datadog provider's authenticated user — typically a CI/CD service account with **Admin** role — not the target service account named in the resource. The key is created successfully with no error, but it inherits the CI/CD SA's Admin scope regardless of any target SA's configured role.

**Always use `datadog_service_account_application_key`** with `service_account_id = datadog_service_account.this[each.key].id` when creating keys for managed service accounts. See [`datadog_service_account_application_key` provider docs](https://registry.terraform.io/providers/DataDog/datadog/latest/docs/resources/service_account_application_key).

**If the wrong resource type already exists in state:**

1. `terraform state rm datadog_application_key.<name>`
2. Revoke the orphaned key in the Datadog UI — `state rm` alone leaves a live Admin-scoped key under the CI/CD SA, which is the worst-of-both outcome (Terraform no longer manages it; Datadog still trusts it).

## Bot review verification

- **Bugbot findings must be verified against actual file paths.** Cursor Bugbot and similar automated reviewers can hallucinate file locations and flag non-issues. Always verify the finding against the actual code before acting on it.
