# Querying Datadog from Agents (HTTP API + optional CLI wrappers)

When AI coding agents need to read Datadog state — logs, monitors, metrics — they can hit the Datadog HTTP API directly. Some teams build a CLI wrapper around the API (e.g., one named `pup`) for convenience; this doc covers the underlying API patterns first, then notes about CLI wrappers.

## Authentication

Two paths — pick whichever fits your environment:

### API + APP keys (non-interactive, CI)

Set `DD_API_KEY` and `DD_APP_KEY` env vars. Both are required — most read-only API calls need both. Store them in your secrets manager and fetch at runtime:

```bash
# Fetch keys from your secrets store. Two common shapes:
#   AWS Secrets Manager:
#     DD_KEYS=$(aws secretsmanager get-secret-value \
#       --secret-id <secret-path> --query SecretString --output text)
#   Local .env (self-hosted / dev):
#     DD_KEYS=$(cat ~/.config/datadog-keys.json)
DD_KEYS="<the JSON blob containing DD_API_KEY and DD_APP_KEY>"
export DD_API_KEY=$(echo "$DD_KEYS" | jq -r .DD_API_KEY)
export DD_APP_KEY=$(echo "$DD_KEYS" | jq -r .DD_APP_KEY)
export DD_SITE="datadoghq.com"   # or datadoghq.eu, ddog-gov.com, etc.
```

### OAuth (interactive, local dev)

If your team uses an OAuth-based CLI wrapper, the typical commands are `<wrapper> auth login`, `<wrapper> auth status`, `<wrapper> auth refresh`. Tokens are stored in the OS keychain and refresh periodically. Refresh before querying if your CLI reports an expired token.

## Common API calls

Logs search:

```bash
curl -s -X POST "https://api.${DD_SITE}/api/v2/logs/events/search" \
  -H "DD-API-KEY: $DD_API_KEY" -H "DD-APPLICATION-KEY: $DD_APP_KEY" \
  -H "Content-Type: application/json" \
  -d '{"filter":{"query":"service:<service>","from":"now-1h","to":"now"},"page":{"limit":5}}'
```

Monitor list / get:

```bash
curl -s -H "DD-API-KEY: $DD_API_KEY" -H "DD-APPLICATION-KEY: $DD_APP_KEY" \
  "https://api.${DD_SITE}/api/v1/monitor"

curl -s -H "DD-API-KEY: $DD_API_KEY" -H "DD-APPLICATION-KEY: $DD_APP_KEY" \
  "https://api.${DD_SITE}/api/v1/monitor/<id>"
```

Metrics query:

```bash
NOW=$(date +%s)
ONE_HR_AGO=$(( NOW - 3600 ))
curl -s -H "DD-API-KEY: $DD_API_KEY" -H "DD-APPLICATION-KEY: $DD_APP_KEY" \
  "https://api.${DD_SITE}/api/v1/query?from=${ONE_HR_AGO}&to=${NOW}&query=avg:system.cpu.user{*}"
```

User list (for verifying on-call schedules):

```bash
curl -s -H "DD-API-KEY: $DD_API_KEY" -H "DD-APPLICATION-KEY: $DD_APP_KEY" \
  "https://api.${DD_SITE}/api/v2/users"
```

Pipe results through `jq` for filtering or shape transforms.

## Key notes

- **Log source tags distinguish collection paths**: `source:java` / `source:nodejs` / `source:typescript` = file tailing; `source:otlp_log_ingestion` = OTLP export. Mixed dashboards that filter on a single `source:*` value silently miss data from the other path.
- **Site depends on tenancy**: `datadoghq.com` (US1), `us3.datadoghq.com` (US3), `us5.datadoghq.com` (US5), `datadoghq.eu` (EU), `ap1.datadoghq.com` (AP1), `ddog-gov.com` (US1-FED). Use the matching `DD_SITE` and API base URL.
- **Both keys required**: most read endpoints need both `DD-API-KEY` and `DD-APPLICATION-KEY`. The API key alone is for write/ingest paths; the APP key authorizes reads.
- **Rate limits**: Datadog enforces per-endpoint rate limits. Bulk queries should add a small delay or back off on `429` responses.

## CLI wrappers

If your team uses a CLI wrapper for convenience (auto-pagination, agent-mode JSON output, OAuth helpers), the patterns above still apply — the wrapper is just a thinner-typing layer over the same HTTP API. Document your wrapper's install path and auth model alongside its source.
