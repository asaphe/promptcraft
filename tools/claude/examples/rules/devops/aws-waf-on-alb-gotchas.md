# AWS WAF on ALB — body inspection limit and per-path exemption pattern

## Body inspection limit

**AWS WAF on ALB can only inspect the first 8 KB of request body. This is a hard AWS limitation — it cannot be increased.** CloudFront and API Gateway support up to 64 KB; ALB does not.

Implications:

- Managed rules that operate on body content (`SizeRestrictions_BODY`, SQLi / XSS body inspection) only see the first 8 KB.
- Any payload greater than 8 KB that passes WAF is **completely uninspected** at the WAF layer for body-based rules — the request body is silently truncated for evaluation.
- Body-based injection attacks in bytes 8,193+ will not be caught.

## Per-path body-size exception pattern

WAFv2 `rule_action_override` applies to all requests evaluated by the managed rule group — it cannot be conditioned on URI path or other request attributes. To exempt a specific path from a managed rule:

1. Override the managed rule to `count` (log-only)
2. Add a custom rule that re-blocks with the path exclusion (using `and_statement` + `not_statement` + `or_statement` + `byte_match_statement` on `uri_path`)
3. Use `oversize_handling = "MATCH"` on the `body` field — without it, WAF truncates to 8 KB before evaluating the size constraint, making `GT 8192` always false (dead rule).

Skeleton:

```hcl
rule {
  name     = "SizeRestrictionsBodyExceptLargePayloadPaths"
  priority = 10

  action { block {} }

  statement {
    and_statement {
      statement {
        size_constraint_statement {
          comparison_operator = "GT"
          size                = 8192
          field_to_match {
            body {
              oversize_handling = "MATCH"   # required — without it, GT 8192 is always false
            }
          }
          text_transformation {
            priority = 0
            type     = "NONE"
          }
        }
      }
      statement {
        not_statement {
          statement {
            or_statement {
              statement {
                byte_match_statement {
                  field_to_match { uri_path {} }
                  positional_constraint = "EXACTLY"
                  search_string         = "/api/large-payload-endpoint"
                  text_transformation {
                    priority = 0
                    type     = "NONE"
                  }
                }
              }
              # add more byte_match_statement blocks for additional exempt paths
            }
          }
        }
      }
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "SizeRestrictionsBodyExceptLargePayloadPaths"
    sampled_requests_enabled   = true
  }
}
```

## Scaling note

This pattern works for a small number of exempt paths. If many endpoints need large body support, consider:

- **CloudFront WAF** — supports up to 64 KB body inspection with configurable limits.
- **Application-level body validation** — per-route body parser limits (Express, Next.js, FastAPI middleware).
- **API Gateway fronting** — configurable WAF body inspection up to 64 KB.

## WAF logging caveat

WAF logging to S3 / CloudWatch / Firehose is opt-in. Without it, debugging relies on:

- `aws wafv2 get-sampled-requests` — sampled view of recent requests per rule metric name (last 3 hours, statistical sample, not exhaustive)
- CloudWatch metrics (`AWS/WAFV2` namespace) — aggregate block / allow counts

WAF blocks return 403 at the ALB layer — requests never reach the application, so application logs won't show them. Sampled requests are the primary evidence source unless logging is enabled. For any environment where WAF blocking is load-bearing, enable WAF logging upfront — the absence is felt only when something breaks and you can't see why.
