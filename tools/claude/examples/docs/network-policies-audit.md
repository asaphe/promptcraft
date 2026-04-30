# NetworkPolicy Audit Checklist (AWS EKS + VPC CNI + Calico)

Reference for authoring or modifying Kubernetes NetworkPolicy / Calico `NetworkPolicy` rules without silently breaking pod connectivity. Scope: **AWS EKS clusters running VPC CNI for networking + Calico in policy-only mode**. The VPC-CNI-specific gotchas don't apply to GKE / AKS or to clusters running Cilium.

## How NetworkPolicy works (for the audit context)

In this setup, **VPC CNI handles networking** and **Calico handles policy enforcement**. Calico runs in policy-only mode alongside VPC CNI — it doesn't replace the data plane. Felix watches NetworkPolicy CRDs and programs iptables on each node.

Tenant namespaces are typically auto-discovered by a label selector your team picks (e.g., a `<your-org>/deployment-id` label). Control-plane namespaces are excluded from the discovery selector.

## Example egress allow set (one workload mix)

The right port list depends entirely on your stack. Build your own from `kubectl get svc -A` + a codebase grep + `/proc/net/tcp` (see the audit checklist below). The list below is one example to illustrate the shape — yours will look different:

- **DNS**: 53/UDP+TCP to kube-dns
- **Intra-namespace**: any port (so the pod can reach its sidecars and dependencies)
- **Pod Identity + IMDS**: `169.254.170.23:80`, `169.254.169.254:80` (link-local — outside VPC CIDR)
- **VPC CIDR TCP**: stack-specific ports (e.g. 4317 / 4318 OTLP, 5432 Postgres, 8123 / 8443 / 9000 / 9440 ClickHouse, 5672 / 5671 RabbitMQ)
- **VPC CIDR UDP**: 8125 (DogStatsD)
- **External HTTPS**: 443 (with optional CIDR allowlist for sensitive workloads)
- **Workflow engines**: 7233 (e.g., Temporal)

## Port Audit Checklist (before enabling / modifying policies)

- **Audit ALL ports from three sources and cross-reference**:
  1. `kubectl get svc -A` for all service `targetPort` and `port` values
  2. Codebase grep for connection strings, env vars, and port literals
  3. `/proc/net/tcp` from running pods for live outbound connections that may not appear in code

  A port missing from the policy causes silent failures.

- **OTEL and DogStatsD fail silently when blocked** — No errors appear in pod logs when traces / metrics drop. Detect via direct socket test:

  ```bash
  python3 -c "import socket; s=socket.create_connection(('NODE_IP', 4317), timeout=3)"
  ```

  Or by noticing missing traces / metrics in your observability tool.

- **ClickHouse has 4 ports** — HTTP (8123), HTTPS (8443), native (9000), native TLS (9440). ClickHouse Cloud uses HTTPS (8443) and native TLS (9440). Internal self-hosted typically uses HTTP and native; both deployments coexist.

- **Don't forget link-local endpoints** — Pod Identity (`169.254.170.23:80`) and IMDS (`169.254.169.254:80`) are outside VPC CIDR and outside RFC1918. They need explicit egress rules. CIDR-only allow lists (e.g. `ipBlock: 10.0.0.0/8`) miss them.

- **VPC CNI `NETWORK_POLICY_ENFORCING_MODE` only accepts `standard` or `strict`** — Setting to `off` or any other value crashes `aws-node` pods. To disable VPC CNI policy enforcement, remove the env var entirely.

- **VPC CNI native NetworkPolicy: `ipBlock` port restrictions don't enforce for pod-to-pod traffic within the cluster** — `ipBlock` rules only filter by CIDR for external (non-pod) IP traffic. Pod-to-pod traffic ignores the `ports` list entirely. This is the original reason teams adopt Calico in policy-only mode alongside VPC CNI.

- **Ingress-only isolation with VPC CNI native requires 100% namespace coverage** — One unprotected namespace breaks isolation for all because the VPC-CIDR ingress rule (needed for ALB) also matches pod IPs.

## SG requirements (Calico-specific)

Node pool security groups must allow cross-node-group traffic on:

- TCP/5473 from VPC CIDR (Calico Typha)
- TCP/7443 from VPC CIDR (Calico Goldmane flow logs)

## Common tasks

- **Add a namespace**: automatic via the label selector — just apply the policy module
- **Add an egress port**: append to the VPC-CIDR-ports list in the policy source (`policies.tf` or equivalent)
- **Emergency disable**: set the policy module's `enabled` flag to `false` and apply, OR `kubectl delete networkpolicies.crd.projectcalico.org -A`
- **Verify isolation**: `kubectl exec -n tenantA deploy/<pod> -- wget --timeout=3 http://<service>.<tenantB>.svc:<port>/health` (should time out)
- **View flows**: with Calico v3.30+ Goldmane / Whisker, `kubectl port-forward svc/whisker 8081:8081 -n calico-system`. No external observability cost — data stays in-cluster.
