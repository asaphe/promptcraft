# IAM trust-policy principal lists must be updated incrementally — AWS rejects ARNs that don't exist

## Symptom

`aws iam update-assume-role-policy` (or `terraform apply` of an `aws_iam_role.assume_role_policy` change) fails with:

```text
MalformedPolicyDocument: Invalid principal in policy: "AWS":"arn:aws:iam::<acct>:role/<name>"
```

The whole policy update is rejected — including the existing principals that were valid.

## Mechanism

When a trust policy lists role/user ARNs as `Principal.AWS`, IAM canonicalizes each ARN to the principal's internal unique ID (e.g. `AROAXXXXXXXX`) at policy-write time. If the role doesn't exist there is no unique ID to canonicalize to, and the entire `UpdateAssumeRolePolicy` call fails — including any other (valid) principals being added in the same call. There is no "soft" or "future" mode.

This canonicalization is also why, when a referenced role is later deleted, the trust policy starts displaying the raw unique-ID token instead of the friendly ARN — the policy stored the ID, not the name.

S3 bucket policies, KMS key policies, and Lambda resource policies do NOT canonicalize — they store the literal ARN string and resolve lazily at access time, which is why those policies happily accept non-existent ARNs.

## Rule

**Trust-policy principal additions must happen incrementally — one new role at a time, after the role exists.** You cannot pre-emptively add a batch of future role ARNs in one PR.

For any migration that introduces multiple new principals on a shared role: the trust update has to be part of each new role's own end-to-end creation cycle, not a one-time batch upfront.

## Applying a trust-policy addition (CLI-first pattern)

The CLI-first workflow exists because of the IAM canonicalization gotcha above (a TF apply that adds a not-yet-existent ARN fails with `MalformedPolicyDocument`). The workflow:

1. Author the new scoped role (separate PR) and apply it.
2. Verify the new role exists: `aws iam get-role --role-name <new-role>`.
3. Backup the current shared role's trust policy:

   ```bash
   aws iam get-role --role-name <shared-role> \
     --query 'Role.AssumeRolePolicyDocument' --output json \
     > /tmp/<shared-role>-trust-backup.json
   ```

4. Confirm the existing trust shape before appending — the `jq += [...]` form below assumes a single statement with `Principal.AWS` as an array:

   ```bash
   jq -e '.Statement | length == 1 and (.Statement[0].Principal.AWS | type == "array")' \
     /tmp/<shared-role>-trust-backup.json
   ```

5. Build the new trust policy by appending the new role's ARN to the existing principal list:

   ```bash
   jq '.Statement[0].Principal.AWS += ["arn:aws:iam::<account-id>:role/<new-role>"]' \
     /tmp/<shared-role>-trust-backup.json > /tmp/<shared-role>-trust-new.json
   ```

6. Apply:

   ```bash
   aws iam update-assume-role-policy \
     --role-name <shared-role> \
     --policy-document file:///tmp/<shared-role>-trust-new.json
   ```

7. Codify the change in the Terraform source for the shared role and open a small follow-up PR.

## Counter-indications

- **Permission policies** (the policies the shared role itself attaches to consumers) DO accept ARNs that don't exist yet. The principal-list-validation behavior is specific to trust policies.
- **Service principals** (e.g. `Service: "lambda.amazonaws.com"`) and **federated principals** (OIDC providers) don't have this validation — they're not role ARNs.
- **Cross-account role/user ARNs** follow the same rule — the principal must exist (in its own account) at write time. The same canonicalization happens.
- **Account root ARNs** (`arn:aws:iam::123456789012:root`) bypass the per-principal-existence check because they reference an account, not a specific principal entity. Use these when you genuinely need account-wide cross-account trust.
