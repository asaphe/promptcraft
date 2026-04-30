# `aws:SourceArn` in log delivery resource policies must use the *source* service namespace

## Symptom

A CWL resource policy (or S3 bucket policy) grants `delivery.logs.amazonaws.com` write access, the
config reports `Status: CREATED` / `AssociationCount: 1`, but no log events arrive. No error surface — the allow
statement simply never matches.

## Mechanism

When `delivery.logs.amazonaws.com` writes to a CloudWatch log group or S3 bucket, the `aws:SourceArn`
context key it presents is the **ARN of the originating AWS resource** (e.g. the Route53 Resolver query
log config, the WAF Web ACL, the VPC flow log), **not** an ARN in the destination service's namespace.

Using `arn:aws:logs:…` as the `ArnLike` value matches the destination's own log group ARN pattern —
it will never match the source ARN that delivery.logs sends.

## Correct patterns by service

| Source service | SourceArn pattern |
|---|---|
| Route53 Resolver query logging | `arn:aws:route53resolver:${region}:${account}:resolver-query-log-config/*` |
| VPC Flow Logs | `arn:aws:ec2:${region}:${account}:vpc-flow-log/*` |
| CloudFront (standard logs) | N/A — uses ACL-based delivery, not delivery.logs |
| WAF logging to S3 | `arn:aws:wafv2:${region}:${account}:*/webacl/*/*` (only if using `aws:SourceArn`; WAF S3 delivery typically uses `s3:x-amz-acl` + `aws:SourceAccount` instead) |

## Rule

**In any resource policy that permits `delivery.logs.amazonaws.com`, always use the source resource's
service namespace (e.g. `route53resolver`, `ec2`) in `aws:SourceArn`, never the destination service's namespace.**

Fetch the correct pattern from AWS docs at authoring time — do not rely on memory or naming conventions.
