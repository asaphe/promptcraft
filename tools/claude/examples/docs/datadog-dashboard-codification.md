# Codifying a Datadog Dashboard into IaC

Procedure for taking a manually-built Datadog dashboard and bringing it under IaC management without losing the existing layout / widgets. Examples below use Terraform; the same flow works with Pulumi or CDK using the equivalent Datadog provider resources.

## When to use

- A dashboard was built manually in the Datadog UI by an SRE / on-call rotation and is now considered "production state" worth versioning
- A team wants to fork an existing canonical dashboard and customize it
- Dashboard changes need a review step before going live (only enforceable via Terraform + PR review)

## Procedure

### 1. Export the dashboard JSON

```bash
DASHBOARD_ID=<id-from-datadog-url>
pup dashboards get "$DASHBOARD_ID" > /tmp/dashboard-raw.json
```

Or via direct API:

```bash
curl -s -H "DD-API-KEY: $DD_API_KEY" -H "DD-APPLICATION-KEY: $DD_APP_KEY" \
  "https://api.datadoghq.com/api/v1/dashboard/$DASHBOARD_ID" \
  > /tmp/dashboard-raw.json
```

### 2. Strip read-only / server-managed fields

The Datadog API returns fields that are **not accepted on POST / PUT** — you must remove them before Terraform can manage the dashboard. Common ones:

- Top-level: `id`, `url`, `author_handle`, `author_name`, `created_at`, `modified_at`, `restricted_roles` (sometimes)
- Per-widget: `id` on every widget and nested group widget

A `jq` one-shot strip:

```bash
jq '
  del(.id, .url, .author_handle, .author_name, .created_at, .modified_at)
  | walk(if type == "object" and has("id") and has("definition") then del(.id) else . end)
' /tmp/dashboard-raw.json > /tmp/dashboard-cleaned.json
```

### 3. Import into Terraform state

Declare a `datadog_dashboard` resource pointing at the cleaned JSON, then import:

```hcl
resource "datadog_dashboard" "example" {
  dashboard_lists = []   # populate as needed
  # ... other top-level fields from the JSON

  dynamic "widget" {
    for_each = local.widgets
    content {
      # ...
    }
  }
}
```

Easier alternative: use the `datadog_dashboard_json` resource which accepts the full JSON as a single attribute:

```hcl
resource "datadog_dashboard_json" "example" {
  dashboard = file("${path.module}/dashboards/example.json")
}
```

```bash
terraform import datadog_dashboard_json.example "$DASHBOARD_ID"
```

### 4. Extract canonical from Terraform state

After `terraform import`, the state contains the canonical form Terraform expects:

```bash
terraform show -json | jq '.values.root_module.resources[] | select(.address == "datadog_dashboard_json.example") | .values.dashboard | fromjson' > /tmp/dashboard-canonical.json
```

Diff `/tmp/dashboard-cleaned.json` against `/tmp/dashboard-canonical.json`. The canonical version is what your repo file should contain — any drift becomes a future plan diff.

### 5. Verify with `terraform plan`

`terraform plan` should output `No changes`. If it shows a diff, the JSON in the repo doesn't match the imported state — adjust the file to match the canonical form. Common drift sources:

- Field ordering (Datadog sometimes reorders; Terraform doesn't)
- Empty arrays vs missing fields
- Boolean defaults
- `template_variable_presets` ordering

## Operational notes

- **Never delete a `datadog_dashboard_json` resource without re-importing or backing up the JSON.** The dashboard is destroyed in Datadog when the resource is removed from state-attached config.
- **Lock the dashboard in the UI** to prevent manual edits while it's Terraform-managed. Set `is_read_only = true` or use the per-team locking mechanism.
- **`restricted_roles`**: if present in the source JSON, decide whether to manage it via Terraform or strip it. Managing it means TF will revert any UI-side role changes, which is sometimes desired and sometimes not.

## Why this exists

Without codification, Datadog dashboards drift silently — someone tweaks a query for a debug session, forgets to revert, and the dashboard now misrepresents the system. Terraform + PR review catches every change.
