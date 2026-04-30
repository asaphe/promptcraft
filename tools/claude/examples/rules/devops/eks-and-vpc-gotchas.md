# EKS & VPC Operational Gotchas

Production-tested operational rules for EKS and VPC networking. Each is a silent failure mode — AWS / Helm / Terraform accept the wrong shape and break later, often visibly only at runtime.

## EKS

### `aws eks update-addon --resolve-conflicts OVERWRITE` strips IRSA injection

Calling `aws eks update-addon` with `--resolve-conflicts OVERWRITE` and without re-stating `--service-account-role-arn` removes the IRSA role binding. The addon update succeeds, but pods that depended on IRSA start failing at AWS API calls (no credentials).

**Fast recovery:** annotate the affected ServiceAccount with `eks.amazonaws.com/role-arn=<role-arn>` and delete stuck pods so the new SA token is mounted on restart. Then re-issue the addon update with `--service-account-role-arn` set.

### Check addon config schema before version bumps

Addon configuration schemas change between versions. A field that was optional in v1 may become required, renamed, or moved. Run this before any version bump:

```bash
aws eks describe-addon-configuration \
  --addon-name <name> \
  --addon-version <version> \
  --query 'configurationSchema'
```

Compare against the current configuration. Drift between the schema and your config means the upgrade will fail or silently strip values.

### Pinned AMI blocks Karpenter drift on control-plane upgrade

Karpenter nodes with a pinned AMI alias (e.g., `EC2NodeClass.amiSelectorTerms[0].alias = al2023@v20240101`) do NOT drift when the EKS control plane is upgraded. The cluster shows the new control-plane version, but data-plane nodes keep the old AMI.

**To cycle:** update the AMI alias in `EC2NodeClass` (or remove the pin), then Karpenter will drift and replace nodes per the disruption budget.

### `do-not-disrupt` annotation for controlled node rollouts

Annotate workloads with `karpenter.sh/do-not-disrupt: "true"` before control-plane upgrades or any planned node-cycling event. Remove the annotation per tier (staging → infra → prod) after each tier validates, so Karpenter rolls nodes in a controlled order rather than all at once.

### Helm does not update CRDs on `helm upgrade`

Helm's CRD lifecycle is asymmetric: `helm install` applies CRDs from `crds/`, but `helm upgrade` does NOT update them. New CRD versions must be applied manually:

```bash
kubectl apply --server-side --force-conflicts -f <crd-url>
```

Symptom of skipping this: new fields in the chart's templates are silently dropped (the API server still has the old CRD schema).

## VPC

### Interface VPC endpoint private DNS shadows public AWS domains

When you create an interface VPC endpoint for a service like `eks` with `PrivateDnsEnabled = true`, AWS auto-creates a private hosted zone (PHZ) for `eks.<region>.amazonaws.com` in the associated VPC. The PHZ is **authoritative for the entire subdomain** — any query, including for unrelated subdomains, gets NXDOMAIN if not explicitly recorded.

Concrete failure mode: `oidc.eks.us-east-1.amazonaws.com` is a public AWS endpoint required for IRSA token exchange. After creating the EKS VPC endpoint, the PHZ shadows it and returns NXDOMAIN for the OIDC subdomain. IRSA breaks; cluster authentication fails for any workload using IRSA.

**Fix:** create a separate PHZ for the specific subdomain (`oidc.eks.us-east-1.amazonaws.com`) with public A records that match the upstream public DNS. This requires periodic refresh of the IPs unless you use a CNAME to a public resolver.

This same pattern applies to other AWS services with PrivateLink: any subdomain not explicitly served by your VPC endpoint will be black-holed by the PHZ.

### Per-hostname PHZs, never parent-domain

When creating a PHZ for a vendor-managed domain (e.g., `cloud.databricks.com`, `<region>.snowflakecomputing.com`), use **per-hostname PHZs** (`workspace1.cloud.databricks.com`, `workspace2.cloud.databricks.com`), not the parent domain. A PHZ for the parent intercepts ALL subdomains and returns NXDOMAIN for any unrecorded one — breaking unrelated control-plane connections.

## Network Diagnostics

### Verify every network layer before declaring "our side is clean"

When debugging connectivity, walk every layer with actual AWS API calls:

1. **Security Groups** — `aws ec2 describe-security-groups` on both source and destination
2. **NACLs** — stateless, so check ingress AND egress rules on both source and destination subnets
3. **VPC Endpoint policies** — `aws ec2 describe-vpc-endpoint-policies` for any private-link path
4. **Route tables** — confirm the route exists and points where expected
5. **DNS resolution** — `dig` from a pod inside the cluster, not from your laptop

One unchecked layer invalidates the diagnosis. Network failures are layered failures.

### Verify resource ownership before diagnosing

Before tracing a failure, confirm the resource is yours and the failure mode is yours to fix:

- Check tags (`CreatedBy`, `TerraformModule`, `Owner`) on the resource
- Check Terraform state (`terraform state show <addr>`)
- If the resource is vendor-managed (Databricks workspace VPC, Snowflake PrivateLink, RDS Aurora), the remediation path is "open a vendor ticket", not "modify Terraform"

Wrong ownership assumption changes the entire remediation approach.
