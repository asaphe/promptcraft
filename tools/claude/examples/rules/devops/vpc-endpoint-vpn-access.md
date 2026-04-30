# Interface VPC endpoints must whitelist VPN client CIDR when PrivateDNS is on

## Symptom

AWS Console panels stall or fail for users on AWS Client VPN, but work when they disconnect. Typically hits service consoles that make XHR calls to regional API endpoints: EC2, CloudWatch, Secrets Manager, RDS, ECR, EKS, etc. Often reported as "only parts of the console are broken on VPN".

## Mechanism

An interface VPC endpoint with `PrivateDnsEnabled = true` creates an authoritative PHZ (e.g. `ec2.us-east-1.amazonaws.com.`) inside the associated VPC. Any resolver query hitting the VPC's resolver — including queries forwarded from an AWS Client VPN endpoint whose `DnsServers` point at VPC+2 — gets the VPCE's **private ENI IP** instead of the public AWS endpoint IP.

The VPN client then tries to TCP-connect to that private IP from its VPN client CIDR (e.g. `172.31.0.0/22`, which sits **outside** the VPC's CIDR). If the VPCE security group ingress only allows the VPC CIDR, the connection is dropped at the SG and the browser hangs.

This is the same root cause as the `oidc.eks.us-east-1.amazonaws.com` stale-PHZ case, just manifesting on a different consumer: there the consumer was `terraform apply` and the symptom was a stale A-record workaround; here it's a browser and the symptom is SG reject.

## Rule

**Any security group attached to an interface VPC endpoint with `PrivateDnsEnabled = true` must include the AWS Client VPN client CIDR in its 443 ingress rule for every VPC that has a Client VPN attached.**

- **Why:** VPN clients inherit the VPC's DNS, so they get VPCE private IPs and must be routable to those ENIs. The VPCE does its own IAM/SigV4 authentication — admitting the VPN CIDR adds no new trust surface.
- **How to apply:** Maintain a workspace-keyed `vpn_client_cidrs` map (or equivalent) in your VPC-endpoints module. When adding a new VPC/workspace with a Client VPN, add an entry for it. An empty list (or absent key) means "no Client VPN, no extra CIDR".

## Counter-indications

- Does **not** apply to gateway endpoints (S3, DynamoDB) — they don't have ENIs or SGs and route via route table entries.
- Does **not** apply to interface endpoints with `PrivateDnsEnabled = false` — DNS falls through to public and no VPCE involvement.
- Does **not** apply to service-to-service PrivateLink endpoints (vendor PrivateLink to ClickHouse, Databricks, observability vendors, etc.) — their consumer is inside the VPC, not a VPN client browser.

> See also: [aws/containers-roadmap #2038](https://github.com/aws/containers-roadmap/issues/2038) — upstream AWS limitation: EKS PrivateLink endpoint does not serve OIDC.
