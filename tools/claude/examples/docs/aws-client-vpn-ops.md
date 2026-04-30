# AWS Client VPN Operational Reference

## Certificate Renewal

- VPN server certs are typically self-signed (TLS provider in Terraform), imported to ACM. They do NOT auto-renew.
- A common validity choice: 3 years for the server cert (26280 hours), 10 years for the CA. Track expiry — there is no automatic renewal.
- **The endpoint does NOT reload certs on ACM re-import.** After renewing a cert via `terraform apply` (targeted or full), you must trigger an in-place endpoint modification to force the reload. A banner-text change or `aws ec2 modify-client-vpn-endpoint --server-certificate-arn <same-arn>` works. A full apply that touches the endpoint resource is the cleanest approach.
- After cert renewal, clients must re-download the `.ovpn` config (the new CA cert is embedded). Export via CLI:

  ```bash
  aws ec2 export-client-vpn-client-configuration \
    --client-vpn-endpoint-id <id> \
    --output text > config.ovpn
  ```

## Self-Service Portal

- The self-service portal is a SAML-authenticated web app provided by AWS. Each VPN endpoint typically has two SAML apps registered with your IdP: one for client auth, one for the self-service portal.
- The self-service portal SAML app **must** have its relay state set to `https://self-service.clientvpn.amazonaws.com/endpoints/<endpoint-id>`. Without this, the portal returns HTTP 400 on the SAML callback.
- ACS URL: `https://self-service.clientvpn.amazonaws.com/api/auth/sso/saml`
- Audience: `urn:amazon:webservices:clientvpn`

## Endpoint inventory

Maintain a per-environment table — example shape, fill with your endpoints:

| Env | Endpoint ID | VPC | Client CIDR |
|-----|------------|-----|-------------|
| prod | `cvpn-endpoint-<id>` | vpc-<id> (`10.x.0.0/16`) | `172.31.0.0/22` |
| stg | `cvpn-endpoint-<id>` | vpc-<id> (`10.x.0.0/16`) | `172.32.0.0/22` |

The Client CIDR is the pool the VPN allocates to connected clients. It must be outside the VPC CIDR and outside any peer VPC CIDR. It must be in the security-group ingress allow lists of any interface VPC endpoints with `PrivateDnsEnabled = true` (see `examples/rules/devops/vpc-endpoint-vpn-access.md`).

## Debugging

- **VPN client logs** (macOS): `~/.config/AWSVPNClient/logs/ovpn_aws_vpn_client_*.log` — contains actual OpenVPN TLS errors. This is the authoritative source for "why is the connection failing."
- **macOS unified logging** (`log stream`) redacts VPN messages behind `<private>` — useless for TLS debugging. Always pull the OVPN client logs directly.
- **Connection logs in CloudWatch** — `{env}-client-vpn` log group (or whatever your env-prefixed convention is) shows assertion success / failure but does not include TLS details.

## Common Failure Modes

- **TLS handshake fails after cert renewal** — endpoint wasn't bumped after ACM re-import; trigger a no-op endpoint modification.
- **HTTP 400 from self-service portal** — relay state missing or wrong on the SAML app.
- **Connected, but can't resolve internal AWS services** — interface VPCE security groups don't include the Client CIDR; see `examples/rules/devops/vpc-endpoint-vpn-access.md`.
- **Cert expiry without renewal pipeline** — there's no AWS-side reminder. Add a calendar event or monitor script that queries the endpoint cert expiry every week.
