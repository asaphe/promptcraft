# ExternalSecret Go template gotchas

When ExternalSecret CRDs use Go templates (via `dataFrom.extract` + `template`), the Go template engine has several behaviors that silently produce wrong output. Each is enforceable in PR review.

## `range` rebinds `.` — use `$` for root context

Inside a `{{ range }}` block, `.` becomes the iteration variable. Accessing the outer (template-root) context requires `$`.

```yaml
# WRONG — `.` here is the iteration item, not the root dict
{{ range .tenants }}
  {{ index . (printf "%s_ch_host" .name) }}
{{ end }}

# CORRECT — `$` is the root
{{ range .tenants }}
  {{ index $ (printf "%s_ch_host" .name) }}
{{ end }}
```

## `keys $dict | sortAlpha` for deterministic output

Go's `dict` iteration is randomized. Without `sortAlpha`, each ESO sync cycle may write textually different (but identical) Secrets, causing API churn — every reconcile loop produces a "changed" Secret even when nothing changed.

```yaml
# CORRECT
{{ range $key := keys $dict | sortAlpha }}
  {{ $key }}: {{ index $dict $key }}
{{ end }}
```

## `toJson` for values with JSON-breaking characters

Raw `"{{ .value }}"` breaks on `"`, `\`, or newlines in the value. Use `toJson` (which produces a fully-quoted JSON string, including the outer quotes — so remove your own outer `"..."`).

```yaml
# WRONG — breaks if .value contains a "
"my_field": "{{ .value }}"

# CORRECT — toJson handles quoting
"my_field": {{ .value | toJson }}
```

## `dataFrom.extract` pulls ALL JSON properties

When using `dataFrom.extract`, every property in the source JSON gets pulled — not just the ones you template. Extra keys are harmless with `mergePolicy: Replace` but may leak with `Merge`. Audit the source JSON to confirm no sensitive fields are unintentionally included.

## Align tenant key prefix convention

When transforming tenant identifiers, apply the same transform consistently across `rewrite.transform` and Go template `dict` access:

```yaml
# rewrite.transform
- conversion: "lowercase"
- replace: { source: "-", target: "" }

# Inside the Go template — use the same convention to look up the secret
{{ $key := lower (replace $tenant.name "-" "") }}
```

A mismatch (one path lowercases, the other doesn't) silently produces an empty value with no error.

## Guard on `length(tenants_in_deployment) > 0`

Zero tenants during initial provisioning produces empty first-tenant references that fail at template render time. Guard with a length check:

```yaml
{{ if gt (len .tenants_in_deployment) 0 }}
  {{ range .tenants_in_deployment }}
    ...
  {{ end }}
{{ else }}
  # fall back to legacy / placeholder
{{ end }}
```

## Filter shared-secret data with `<TENANT_NAME>` regex (advanced — narrow case)

> Skip unless your module mixes YAML-templated overrides with HCL-defined data entries. Most ESO setups don't.

When a module uses YAML overrides (`templatefile()`-rendered) alongside HCL-defined data entries, the YAML path is rendered BEFORE the multi-tenant filter runs. To prevent leakage of tenant-templated entries into shared secrets, filter explicitly by regex:

```hcl
shared_secret_data = {
  for k, v in local.tenant_secret_data : k => v
  if !can(regex(".*<TENANT_NAME>.*", k))
}
```

(This applies to modules with YAML overrides; HCL-only modules don't need the filter because they never see `<TENANT_NAME>` strings.)
