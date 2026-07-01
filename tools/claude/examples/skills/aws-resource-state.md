---
name: aws-resource-state
description: Fetch live AWS resource state for an ARN/name before asserting facts about it. Use to verify "role exists", "secret has value", "bucket policy is X", etc. Usage - /aws-resource-state <service> <identifier> [profile]
user-invocable: true
allowed-tools: Bash(AWS_PROFILE=* aws iam *), Bash(AWS_PROFILE=* aws secretsmanager *), Bash(AWS_PROFILE=* aws ssm *), Bash(AWS_PROFILE=* aws s3api *), Bash(AWS_PROFILE=* aws ec2 *), Bash(AWS_PROFILE=* aws eks *), Bash(AWS_PROFILE=* aws ecr *), Bash(AWS_PROFILE=* aws sts *), Bash(AWS_PROFILE=* aws kms *), Bash(AWS_PROFILE=* aws elbv2 *), Bash(AWS_PROFILE=* aws rds *), Bash(AWS_PROFILE=* aws lambda *), Bash(AWS_PROFILE=* aws sqs *), Bash(jq *), Bash(rtk proxy aws *)
argument-hint: "<service> <identifier> [profile]"
---

# aws-resource-state

Authoritative `describe`/`get` wrapper for live AWS resource state. Use BEFORE asserting that any AWS resource exists, has a specific value, or is in a given state. Terraform state, repo grep, and memory are NOT live truth — `describe` is.

## Why this exists

Pre-claim guard. The failure mode this prevents: claiming "the role exists / the secret has value X / the trust policy allows Y" from `grep` against the local repo, only to discover at apply/runtime that AWS-side state diverges. Per your "verify don't assume" rule: before stating any fact about infra, read the actual live state.

## Steps

### 1. Parse arguments

Expected: `<service> <identifier> [profile]` where:

- `<service>` ∈ {`iam-role`, `iam-policy`, `iam-trust`, `secret`, `ssm`, `s3-bucket`, `s3-policy`, `kms`, `eks`, `ecr`, `vpc`, `sg`, `rds`, `lambda`, `sqs`, `alb`}.
- `<identifier>` is the resource name or ARN (no quoting, no leading `arn:` required when service implies it).
- `[profile]` defaults to `prod`. Substitute whatever named profiles your setup uses (e.g. `dev`, `mgmt`).

If `<service>` or `<identifier>` is missing, ask the user.

### 2. Dispatch

Use the per-service command. Always prefix `AWS_PROFILE=<profile>` per-call.

| Service | Command |
|---|---|
| `iam-role` | `AWS_PROFILE=<p> aws iam get-role --role-name <name>` |
| `iam-policy` | `AWS_PROFILE=<p> aws iam get-role-policy --role-name <role> --policy-name <pol>` (caller must split name) OR `aws iam list-attached-role-policies --role-name <role>` |
| `iam-trust` | `AWS_PROFILE=<p> aws iam get-role --role-name <name> --query 'Role.AssumeRolePolicyDocument'` |
| `secret` | `AWS_PROFILE=<p> aws secretsmanager describe-secret --secret-id <name>` (NEVER `get-secret-value` unless user explicitly asked) |
| `ssm` | `AWS_PROFILE=<p> aws ssm get-parameter --name <path>` |
| `s3-bucket` | `AWS_PROFILE=<p> aws s3api head-bucket --bucket <name>` |
| `s3-policy` | `AWS_PROFILE=<p> aws s3api get-bucket-policy --bucket <name> --query Policy --output text \| jq .` |
| `kms` | `AWS_PROFILE=<p> aws kms describe-key --key-id <id-or-arn>` |
| `eks` | `AWS_PROFILE=<p> aws eks describe-cluster --name <name>` |
| `ecr` | `AWS_PROFILE=<p> aws ecr describe-repositories --repository-names <name>` |
| `vpc` | `AWS_PROFILE=<p> aws ec2 describe-vpcs --vpc-ids <id>` |
| `sg` | `AWS_PROFILE=<p> aws ec2 describe-security-groups --group-ids <id>` |
| `rds` | `AWS_PROFILE=<p> aws rds describe-db-instances --db-instance-identifier <id>` |
| `lambda` | `AWS_PROFILE=<p> aws lambda get-function --function-name <name>` |
| `sqs` | `AWS_PROFILE=<p> aws sqs get-queue-attributes --queue-url <url> --attribute-names All` |
| `alb` | `AWS_PROFILE=<p> aws elbv2 describe-load-balancers --names <name>` |

### 3. Token-safety wrapper

For any command whose output drives a decision, prefix `rtk proxy` to bypass RTK filtering — silent truncation has produced wrong reads in the past.

```bash
rtk proxy AWS_PROFILE=<p> aws iam get-role --role-name <name>
```

### 4. Failure modes — report verbatim, don't paper over

| Error | Meaning | Action |
|---|---|---|
| `NoSuchEntity` / `ResourceNotFoundException` | Resource doesn't exist | Report — the claim is false |
| `AccessDenied` | Profile lacks permission | Surface profile + role; suggest correct profile |
| `ParameterNotFound` (ssm) | Path wrong or in different region | Confirm region; check your default `<region>` |
| `ExpiredToken` / `InvalidClientTokenId` | SSO session expired | Surface to user; `aws sso login --profile <p>` |

### 5. Report

Include in the response:

1. The exact command run (with profile).
2. The relevant fields from the response (NOT the whole blob — pick what matters).
3. One-line conclusion about the claim being verified.

## Counter-indications

- **Do not use `get-secret-value` or any read-of-actual-value variant** unless the user explicitly asks for the secret material. `describe-secret` answers "does it exist / when rotated / who manages it" without exposing the value.
- Do not use for resources the local clone is authoritative on (Terraform code, repo configs) — `Read` is cheaper.
- Do not loop this skill to enumerate (e.g., "describe all 200 roles"). For listing use `aws iam list-roles` directly and accept the cost.
- For non-AWS state — your auth provider, data warehouse, or observability platform — defer to a domain-specific tool or agent; this skill is AWS-only.
