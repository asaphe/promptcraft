# A security group whose rules a sibling module also manages must use standalone rule resources — and `ingress`/`egress` are `Computed`, so converting needs `import`, not just block removal

## Symptom

Two Terraform modules manage rules on the **same** security group: one owns the SG via `aws_security_group` with inline `ingress`/`egress` blocks; another attaches a standalone `aws_vpc_security_group_ingress_rule` / `aws_vpc_security_group_egress_rule` (or `aws_security_group_rule`) to that same SG by ID.

Every apply of the inline-block module **strips** the sibling's standalone rule; the sibling's next apply re-adds it. Between the two, whatever the stripped rule allowed (cross-service ingress, a peer's access) is broken — with no error surface, only the dropped connectivity. The AWS provider documents this: inline rules are authoritative and "may cause rule conflicts, perpetual differences, and result in rules being overwritten."

When you go to fix it by deleting the inline blocks, the live rules are **not** revoked and a new standalone rule of the same shape collides:

```text
InvalidPermission.Duplicate: the specified rule ... already exists
```

## Mechanism

Two distinct provider behaviors compound:

1. **Authority.** An inline `ingress`/`egress` block makes the SG authoritative *for that direction*: on every apply the provider revokes any rule of that direction not present in the block. A rule added by another module is, by definition, not in the block → revoked. (Authority is per-direction: an inline `egress` block does not assert authority over `ingress`.)

2. **`Computed`.** `aws_security_group.ingress` and `.egress` are `Optional: true, Computed: true`. **Removing the inline block from config does not revoke the live rules** — the provider reads them back as computed and leaves them in place (the plan shows no `ingress`/`egress` rule diff — only whatever else changed on the SG). So the live inline rule persists, and a standalone resource of the same protocol/port/source then fails to create with `InvalidPermission.Duplicate`. Setting `ingress = []` *would* revoke them, but an explicit empty list is authoritative-empty and will flap against any standalone rule on the same SG.

A third, independent gotcha governs egress specifically: a brand-new `aws_security_group` created with **no** `egress` argument is given AWS's default `0.0.0.0/0` allow-all egress. Pure-standalone egress cannot suppress that default (only an authoritative `egress = []` can, which flaps). So converting egress to standalone silently *widens* new instances' egress to `0.0.0.0/0`.

## Rule

**When a security group's rules are co-managed by a sibling module, make the co-managed direction standalone; do not rely on removing inline blocks alone, and migrate existing instances with `import`.**

1. **Only the co-managed direction needs to go standalone.** If the sibling adds only ingress, convert only `ingress` to a standalone resource and **keep `egress` inline** — inline egress preserves the intended (non-`0.0.0.0/0`) egress and conflicts with nothing. Converting a direction no one else touches adds migration cost and an egress-widening risk for zero benefit.
2. **Migrate existing instances with `terraform import`, per workspace.** Because the live inline rule is not revoked by block removal, the standalone resource must adopt it (`terraform import <addr> <sgr-id>`) before the first apply, or the create collides. New instances need no import — the standalone rule is created fresh.
3. **Verify the converted SG is non-authoritative** by adding a throwaway rule out-of-band, confirming a plan does **not** propose removing it (and that a re-plan of both co-managing modules is 0-change), then removing the throwaway rule. Do this on a zero-consumer instance before any production apply.

## Counter-indications

- Does **not** apply to a security group whose rules are owned by exactly one module — inline blocks are simpler and correct there.
- Does **not** apply when intentionally consolidating ownership into the inline-block module (codifying the sibling's rule there and removing it from the sibling) — then inline blocks are correct, provided the inline module can resolve the referenced source at apply time.
- The default-`0.0.0.0/0`-egress concern is specific to egress; ingress has no implicit default rule.
