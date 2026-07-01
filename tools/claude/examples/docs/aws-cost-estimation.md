# AWS Cost Estimation — methodology gotchas

Estimate from billed usage (Cost & Usage Report / Cost Explorer), not from provisioned-resource math. Several services bill on actual consumed bytes/units that are far smaller than the provisioned figure, so multiplying capacity × unit-price overestimates — sometimes by an order of magnitude.

## RDS automated backups & snapshots

- **Billed on actual compressed + deduplicated backup bytes consumed**, surfaced in the CUR — **not** `AllocatedStorage × $0.095/GB`.
- The provisioned-size formula overestimates badly: an `AllocatedStorage`-based estimate can read ~10× higher than the CUR run-rate, because backups compress and dedup against prior snapshots, so consumed bytes ≪ provisioned DB size.
- **How to get the real number:** pull the backup/snapshot line items from the CUR (or Cost Explorer filtered to the RDS backup usage type) for a recent window and annualize — don't derive from DB size.

## General rule

Before quoting any AWS cost figure: if the estimate came from `capacity × unit_price`, verify against the CUR/Cost Explorer billed line items first. Capacity-based math is an upper bound, not the bill.
