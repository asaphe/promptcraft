# OpenTelemetry: `Resource.create()` overrides `OTEL_RESOURCE_ATTRIBUTES`

## Symptom

`OTEL_RESOURCE_ATTRIBUTES=service.name=my-service` is set in the pod's environment, but traces / metrics / logs in the observability backend show a different `service.name`. Renaming the env var has no effect.

## Mechanism

In the OpenTelemetry Python SDK (and most other language SDKs), attributes passed to `Resource.create()` programmatically **win over** values from the `OTEL_RESOURCE_ATTRIBUTES` environment variable. The merge order favors explicit over implicit:

```python
from opentelemetry.sdk.resources import Resource

# This Resource.create() overrides any service.name in OTEL_RESOURCE_ATTRIBUTES
resource = Resource.create({"service.name": "my-service"})
```

Once `service.name` is set in code, no env var override will change it. The env var is the fallback for attributes not set programmatically.

## Rule

**When introducing or moving `service.name` (or any resource attribute) for an OpenTelemetry-instrumented application, audit both the code path AND the env var.** If the attribute is set both ways, the code wins — silently — even when the env var looks like the source of truth.

For consistency:

- Set resource attributes in **one** place per attribute. Prefer code for attributes that are intrinsic to the service (`service.name`, `service.namespace`).
- Use `OTEL_RESOURCE_ATTRIBUTES` for attributes that vary by environment (`deployment.environment`, `cloud.region`, `host.name`).
- Document which path owns each attribute in your service's instrumentation README.

## Counter-indications

- Does not apply to LogRecords / trace spans where the attribute is set per-event, only to Resource-level attributes.
- Does not apply to attributes auto-detected by SDK resource detectors (cloud metadata, container ID) — those follow their own merge precedence per SDK.

## Verification

In a running pod, the actual resource attributes can be observed in the exported trace / metric / log:

```bash
# Capture an OTLP export and inspect the resource block
# (specific command depends on the protocol — gRPC/HTTP — and the test endpoint)
```

Or read the SDK initialization code path in the application — `Resource.create()` calls and merges are usually in a small handful of files near the OTel setup.
