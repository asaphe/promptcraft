# Moving a Terraform-managed resource between modules

When a resource is in the wrong module — e.g., a policy attachment defined in module A but logically belonging with the role defined in module B — move it via state operations, NOT by destroy-and-recreate. Destroy-and-recreate breaks dependent systems for the duration of the gap; state-move keeps the AWS-side resource untouched throughout.

## When to use

- A resource is logically misplaced (e.g., a policy attachment in `core/` referencing a role defined in `eks/oidc/`).
- A module is being split or consolidated and resources need to relocate.
- A resource was originally created in the wrong module due to chicken-and-egg constraints that no longer apply.

## Playbook

Six phases. Source = current owner of the resource. Target = new owner.

**(a) Add resource + `import` block in the target module.** Declare the resource in the target's `.tf` files. Add an `import` block (or use `terraform import` CLI) referencing the existing AWS object's id. The import block is one-shot — remove after first apply unless the target module follows a "persistent imports.tf" pattern.

**(b) `terraform apply` target.** With the import block, this brings the resource into the target's state without recreating it in AWS. Plan output should be `1 imported, 0 added, 0 changed, 0 destroyed`. If anything else shows, abort and investigate.

**(c) `terraform state rm` from source.** Remove the resource from the source module's state file. This does NOT touch AWS — it tells Terraform "I'm no longer managing this." Use `terraform state rm '<resource address>'`.

**(d) Remove the resource block from source code.** Delete the `resource` declaration (and any matching `import` block if persistent) from the source module's `.tf` files.

**(e) `terraform apply` source.** With the resource block gone and the state already cleaned, plan output should be `0 changes`. This is a no-op apply that confirms the source module is clean.

**(f) Verify both modules drift-free.** Run `terraform plan` in each — both must return "No changes."

## Safety considerations

- **Dual-ownership window** — between (b) and (c), both states reference the same AWS resource. This is safe because both states match AWS exactly; AWS itself is unchanged. Risk is only if someone runs `terraform destroy` against the source during that brief window. Sequence (b) → (c) → (d) → (e) tightly to keep the window short.
- **Verify no in-flight CI applies on either module before starting.** Both source and target are typically CI-driven; check the latest workflow run status. A concurrent apply mid-sequence can race for the state lock and produce undefined state.
- **Audit references before removing the resource block.** `grep -r '<resource_address>'` across the source module. If any other resource consumes the moved resource's attributes (ARN, ID, name) via local interpolation, update those references to read from the target module's state via `terraform_remote_state` or hardcoded value before (d) — otherwise source `terraform plan` will fail with "reference to undeclared resource."
- **Don't move while the original creating PR is still in flight.** State moves assume the resource exists with a stable AWS-side ID. If the resource was just introduced and the creating apply hasn't fully landed across all replicas / regions / dependent state, the import target may be inconsistent.
- **Cross-module dependencies** — if the target module has an apply order constraint (e.g., needs to run after another module), respect that. The state move shouldn't break ordering.
- **Backup before mutating** — `terraform state pull > /tmp/source-state-backup.json` in the source module before (c). State recovery is harder than file recovery.
- **PRs** — typically one PR per module if the modules have separate state and CI. Document the cross-PR sequence in both PR bodies. If both modules are in the same repo, one PR works.

## Anti-patterns

- **Don't destroy and recreate.** AWS resource interruption, dependent system fallout, lost identifiers (e.g., role unique-IDs change, breaking trust policies elsewhere).
- **Don't rely on `terraform state mv` across modules with different remote backends.** The operation is technically supported via `-state-out` after pulling both states locally, but it's fragile (race with concurrent applies, manual state push) and offers no advantage over the import-block flow in (a)–(b). Stick to imports.
- **Don't skip the `import` block in (a) and let `terraform apply` create the resource.** Even if AWS-side `AttachRolePolicy`-style operations are idempotent, you'd end up with the resource in BOTH states with both modules thinking they own it. Use import explicitly to bring it in cleanly.
- **Don't leave the `import` block in target after the first apply** unless the module follows a persistent-`imports.tf` pattern (e.g., bootstrap / recovery modules). A stale import block in `.tf` produces no error but signals the move isn't complete to readers and re-runs the import as a no-op refresh on every plan, slowing CI.

## Verification commands

```bash
# Pre-move: confirm the resource exists in source state
terraform state list | grep '<resource>'

# Pre-move: confirm AWS has the resource (don't trust state alone)
aws iam get-role-policy --role-name <role> --policy-name <policy>

# Post-(b): confirm target now owns it
cd <target-module> && terraform state list | grep '<resource>'

# Post-(c): confirm source no longer references it
cd <source-module> && terraform state list | grep '<resource>'   # expect empty

# Final drift check
cd <source-module> && terraform plan   # expect: No changes
cd <target-module> && terraform plan   # expect: No changes
```
