# ElastiCache `auth_token_update_strategy` fails plan validation whenever the token is unknown — default it to `null` and rotate deliberately in two phases

## Symptom

A Terraform plan for an `aws_elasticache_replication_group` with `auth_token` sourced from `random_password` fails with:

```text
Error: "auth_token_update_strategy": "auth_token" must be specified
```

The token *is* specified in config. The failure fires on **every fresh create** and on **every regeneration** of the `random_password` — exactly the cases where rotation tooling wants a strategy set.

## Mechanism

The AWS provider's plan-time validation (`authTokenUpdateStrategyValidate` in `internal/service/elasticache/replication_group.go`) reads `auth_token` via `diff.GetOk(...)`, which reports an **unknown-at-plan** value as *not specified*. A token coming from `random_password` is unknown at plan on create and on regeneration, so any non-null strategy fails validation in those cases. The check is strategy-agnostic except for `DELETE` — `SET` fails identically to `ROTATE`.

This is **not** fixed by a provider upgrade (present through 6.49.0 and on `main`). The future clean fix is the write-only `auth_token_wo` / `auth_token_wo_version` arguments, still open at <https://github.com/hashicorp/terraform-provider-aws/issues/42239>.

## Rule

**Default `auth_token_update_strategy` to `null`** so create and steady-state plans never carry a strategy and the validation never fires.

**Pin the `random_password` with `lifecycle { ignore_changes = all }`** — `random_password` marks every generation param (`length`, `special`, `override_special`, `min_*`, `numeric`, `upper`, `lower`) as force-new, so a partial allow-list would let a future edit to any unlisted param silently rotate a live token. `all` pins the token to a single generation; deliberate rotation is `-replace` only. `ignore_changes` never affects creation, so new deployments still create with the current charset.

## Deliberate rotation (two-phase — required by the provider)

The two phases exist only to get past the plan-time validation: phase 1 makes the new token value known in state so phase 2 can carry the strategy.

1. Regenerate the token and land its value in state:

   ```bash
   terraform apply -target=random_password.auth_token -replace=random_password.auth_token
   ```

   `-replace` is required because `ignore_changes = all` blocks config-driven regeneration. **This updates only the token value in state — the live cache and the secret are still on the old token and are rotated in step 2. Do not stop between steps:** an aborted run leaves state ahead of the live cache/secret, which the *next* `terraform apply` (strategy back to `null`) reconciles by rotating with the server-side default (ROTATE).

2. Apply with the strategy set (passed as a `-var`, not committed) — the token is now known, so validation passes and the replication group + secret rotate in one apply:

   ```bash
   terraform apply -var 'auth_token_update_strategy=ROTATE'
   ```

   `ROTATE` keeps the old token valid alongside the new during the change — seamless, no app restart, no consumer auth gap. **Prefer `ROTATE`.** `SET` is accepted by AWS only *after* a prior `ROTATE` and swaps immediately, opening a brief window where the cache holds the new token while the secret store still serves the old one (the secret-version resource is written after the cluster modify when it depends on the cluster) — consumers reconnecting in that window fail until they re-read the secret.

3. Consumers must re-read the secret *after* step 2 completes. Nothing to revert: the strategy was passed via `-var`, so the next steady-state `terraform apply` defaults back to `null` automatically.

## Counter-indications

- Even with `auth_token_update_strategy = null`, when the token value changes on an existing replication group AWS defaults the modify to `ROTATE`, so steady-state token changes remain seamless. The explicit `-var 'auth_token_update_strategy=ROTATE'` in phase 2 is only needed to satisfy the plan-time validation while making the change deliberate.
- None of this applies if the token is a known literal at plan time (e.g. read from a data source resolved at plan) — the validation passes and a single apply suffices.
