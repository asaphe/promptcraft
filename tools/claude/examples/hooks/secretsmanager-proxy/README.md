# Secretsmanager Proxy — retired from this repo

This hook has been withdrawn, not just moved. If you installed it, remove it.

It rewrote `aws secretsmanager get-secret-value` and `batch-get-secret-value` to run through
a token-optimization bypass (`rtk proxy …`) so the JSON would not be truncated. That solved a
real formatting problem by guaranteeing the opposite of what you want from a secret
command: the full plaintext value reaching the model's context and the session transcript
intact, on every call.

## What to use instead

**[claude-secret-guard](https://github.com/asaphe/claude-secret-guard)** treats those two
commands as the exposure they are — it blocks them when called directly and points at
`scripts/sm-cache.sh`, a drop-in replacement that fetches once per session, caches the value
at mode 600 under `/tmp/sm-cache-<session-id>/`, and prints a masked confirmation plus the
cache path instead of the value. Reference it downstream as `$(cat <printed-path>)`; pass
`--reveal` on the rare occasion you actually need to see it.

```text
/plugin marketplace add asaphe/claude-secret-guard
/plugin install secret-guard@claude-secret-guard
```

`scripts/aws-batch-secrets.sh` covers `batch-get-secret-value` the same way, and reports
`Fetched N of M` so a partial batch cannot read as a complete one.

## The general lesson

A hook that rewrites a command to widen its output is making a security decision on the
model's behalf. Truncated output is a nuisance; a plaintext secret in a transcript outlives
the session. If output filtering is mangling a command you need, fix it at the command —
select the field you need, or route through a wrapper that masks — rather than by disabling
the filter for the one class of command whose output is most worth withholding.
