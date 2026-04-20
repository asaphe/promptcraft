# Cost Optimization

Guidance for making cost-aware infrastructure and architecture decisions.

## Framing

Cost is a design constraint, not an afterthought. Every external service, compute instance, or managed offering carries ongoing operational cost — treat it like any other quality attribute (security, reliability, performance).

## Infrastructure Preferences

- **Prefer self-hosted / owned compute** when security, compliance, and operational overhead allow.
- **Evaluate managed services against their TCO** — the sticker price of a managed DB is often 3–10× a self-hosted equivalent; the convenience is sometimes worth it, sometimes not. Compute both.
- **Right-size before scaling out.** Undersized instances create flaky services; oversized instances burn money. Measure actual utilization before picking a size.
- **Autoscaling matters more than fixed capacity.** A workload that goes idle nightly should scale to zero (or near-zero) when idle.

## Service Selection

- **Evaluate cost-benefit explicitly** for any external / third-party service. Write down the monthly cost, what it replaces in-house, and the migration cost of removing it.
- **Prefer solutions that scale to zero** (serverless, event-driven, spot compute) for intermittent workloads.
- **Factor in egress.** Cloud egress pricing dominates TCO for data-heavy workloads — co-locate compute with data.
- **Document cost assumptions in ADRs.** Future readers need to know why you picked option A over B; "option B was 4× the cost at our scale" is a legitimate driver.

## Common Waste Patterns

- Idle dev/staging environments running 24/7 — schedule down overnight and on weekends.
- Oversized database instances provisioned for peak + 2× headroom that never materializes.
- Unused load balancers, NAT gateways, and elastic IPs left behind after teardowns.
- Log retention defaults that keep multi-TB per month of low-value logs indefinitely.
- `gp2` / generation-behind instance types still running because "it works" — newer generations are often cheaper *and* faster.
