# S3 `expiration` with versioning enabled requires paired `noncurrent_version_expiration`

## Symptom

S3 bucket has versioning enabled. A lifecycle rule uses `expiration` to clean up objects after N days. Storage costs grow unbounded despite the rule — versions accumulate silently.

## Mechanism

When versioning is on, `expiration` does **not** delete the current object — it writes a delete marker. The previous version becomes "noncurrent" and is never touched by the `expiration` rule. Without `noncurrent_version_expiration`, those previous versions accumulate forever.

For unversioned buckets, `expiration` deletes objects directly. The behavior diverges only when versioning is enabled.

## Rule

**Every `aws_s3_bucket_lifecycle_configuration` rule that uses `expiration` on a versioning-enabled bucket must also include `noncurrent_version_expiration`.**

```hcl
rule {
  id     = "expire-objects"
  status = "Enabled"

  expiration {
    days = 30
  }

  noncurrent_version_expiration {
    noncurrent_days = 30
  }
}
```

## Counter-indications

- Does **not** apply to buckets with versioning disabled — `expiration` alone is correct.
- Does **not** apply if historical versions are intentionally retained.
