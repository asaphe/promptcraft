# Identity Store objects (groups, users, memberships) are SCIM-managed — never `resource`

## Symptom

Plan shows perpetual drift on `aws_identitystore_group_membership` or `aws_identitystore_user`. Specifically: TF removes a member → next plan shows the same removal pending. Or: a TF-side attribute update (display name, email) reverts on the next plan. Plans never converge.

Or: a `terraform destroy` on an Identity Store group fails repeatedly with the resource being recreated within seconds.

## Mechanism

When the IAM Identity Center instance is configured with an external IdP using **automatic provisioning via SCIM**, AWS treats the IdP as the source of truth for the Identity Store directory. Per AWS docs:

> After setting up automatic provisioning with SCIM, you can no longer add or edit users in the IAM Identity Center console. If you need to add or modify a user, you must do so from your external IdP.

There is no outbound sync from AWS Identity Store to the IdP. So if Terraform mutates an SCIM-pushed object:

- TF removes a group member → SCIM re-adds on the next push
- TF updates a user's `display_name` → next SCIM push clobbers it
- TF destroys a group → SCIM recreates within seconds

The provider's plan loop has no way to break out — it sees the AWS-side state that doesn't match config and tries to converge again.

## Detection

`aws identitystore list-groups` does **not** return `CreatedBy` / `UpdatedBy`, only `ExternalIds`. **`ExternalIds` is unreliably populated for groups** — it can be `null` even for SCIM-pushed groups. Use `describe-group` per group and check `CreatedBy` / `UpdatedBy`:

```bash
aws identitystore describe-group \
  --identity-store-id <id> --group-id <gid> \
  --query '{CreatedBy:CreatedBy, UpdatedBy:UpdatedBy}'
```

A `SCIM/<tenant-id>` value indicates the object is owned by the IdP. For users, `list-users` does populate `ExternalIds` correctly with the SCIM `Issuer` ARN — both signals agree.

## Rule

**For any Identity Store group or user that is SCIM-pushed by your IdP, Terraform must reference it via `data` source only. Never declare a `resource "aws_identitystore_group"`, `aws_identitystore_user`, or `aws_identitystore_group_membership` for a SCIM-managed object.**

The canonical lookup pattern:

```hcl
data "aws_identitystore_group" "by_name" {
  for_each          = local.unique_groups   # auto-derived from JSON config
  identity_store_id = tolist(data.aws_ssoadmin_instances.this.identity_store_ids)[0]
  alternate_identifier {
    unique_attribute {
      attribute_path  = "DisplayName"
      attribute_value = each.value
    }
  }
}
```

The authorization layer (permission sets, attachments, account assignments, ABAC mappings) is fully owned by Terraform — those are AWS-side concepts, not directory concepts, and SCIM does not touch them.

## Counter-indications

- Does **not** apply to groups created natively in IAM Identity Center *before* SCIM was enabled and never claimed by SCIM. These can be `resource`-managed if you really need to. Verify via `describe-group` — `CreatedBy` should NOT contain `SCIM/`.
- Does **not** apply to permission sets, even though they're under the `aws_ssoadmin_*` umbrella. PSes are AWS-native; SCIM doesn't touch them.

## Counter-example

Console-managed break-glass permission sets (intentionally excluded from Terraform for recovery-path independence) follow a separate "data-source-only" boundary with a different rationale. Both rules can apply to the same module.
