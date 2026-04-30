# CWL subscription filter → Firehose: known pitfalls

## Native Decompression processor breaks PutSubscriptionFilter

Firehose's `Decompression` and `CloudWatchLogProcessing` processors are incompatible with
`PutSubscriptionFilter`'s test message delivery. CWL sends a CONTROL_MESSAGE test event
during subscription filter creation; native processors reject it, causing permanent failure
regardless of timing (`time_sleep` does not help).

**Use a Lambda transformation instead.** The Lambda decompresses GZIP, extracts log event
messages, and drops CONTROL_MESSAGEs explicitly.

References: [terraform-provider-aws#17049](https://github.com/hashicorp/terraform-provider-aws/issues/17049), [aws-cdk/discussions/34433](https://github.com/aws/aws-cdk/discussions/34433)

## CWL trust policy SourceArn must be account-wide

The IAM role assumed by `logs.{region}.amazonaws.com` for CWL→Firehose delivery requires
`aws:SourceArn` scoped to at least `arn:aws:logs:{region}:{account}:*`. Scoping to a specific
log group ARN blocks `PutSubscriptionFilter`'s test message, which uses a different source context.

## Lambda buffer sizing: 0.5 MB max

CWL records compress ~10x. A Firehose-to-Lambda buffer of 3 MB produces ~30 MB decompressed
output, exceeding Lambda's 6 MB synchronous response limit (HTTP 413). Use `BufferSizeInMBs = 0.5`
and `memory_size >= 256` to handle decompression safely.
