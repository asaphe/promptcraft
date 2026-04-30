# SSO account assignments must explicit-`depends_on` every attachment on the permission set

## Symptom

`aws_ssoadmin_account_assignment.X` fails intermittently on first apply with a
`ConflictException` or a generic `ProvisionPermissionSet` error. Retrying the apply
often succeeds, which makes the failure look like flaky AWS rather than a graph ordering bug.

## Mechanism

`aws_ssoadmin_account_assignment` has an **implicit** dependency on `aws_ssoadmin_permission_set`
via its `permission_set_arn` reference. It does **not** have implicit dependencies on
the attachment resources for that same permission set:

- `aws_ssoadmin_managed_policy_attachment`
- `aws_ssoadmin_customer_managed_policy_attachment`
- `aws_ssoadmin_permission_set_inline_policy`

None of these are referenced by the assignment, so Terraform is free to schedule the
assignment concurrently with the attachments. AWS IAM Identity Center's
`CreateAccountAssignment` API call triggers its own `ProvisionPermissionSet` under the hood,
which rejects if the permission set is already being provisioned due to an in-flight
attachment change. Result: intermittent first-apply failures, clean retries.

## Rule

**Every `aws_ssoadmin_account_assignment` must list every attachment on the
permission set it targets in an explicit `depends_on` block** — managed, customer-managed,
and inline. Implicit dependencies only cover the permission set resource itself.

```hcl
resource "aws_ssoadmin_account_assignment" "example" {
  permission_set_arn = aws_ssoadmin_permission_set.example.arn
  # ...

  depends_on = [
    aws_ssoadmin_managed_policy_attachment.example_support,
    aws_ssoadmin_managed_policy_attachment.example_guardduty,
    aws_ssoadmin_customer_managed_policy_attachment.example_ecr,
    aws_ssoadmin_permission_set_inline_policy.example_inline,
  ]
}
```

## Counter-indications

- Does **not** apply to assignments against a permission set that has **zero** attachments
  (pure PS with only base properties — rare). In that case the implicit `permission_set_arn`
  reference is the only dependency and that's correct. A PS with even one attachment still
  requires that attachment listed explicitly.
- Does **not** apply when the assignment is in a different module / state from the
  attachments — cross-module ordering must be handled by apply order, not `depends_on`.
