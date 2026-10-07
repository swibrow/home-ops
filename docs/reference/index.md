# Reference

Quick-reference tables and catalogs for the cluster.

---

## Sections

| Page | Description |
|:-----|:------------|
| [IP Allocation](ip-allocation.md) | Networks, node and LoadBalancer addresses, and DNS records |
| [App Catalog](app-catalog.md) | Full catalog of all applications deployed in the cluster |

---

## Quick Links

### Network

- **Domain**: `wibrow.dev` (Cloudflare-managed)
- **Kubernetes API VIP**: `10.20.10.0:6443`
- **Nodes**: `10.20.10.1` - `10.20.10.11` (VLAN 20, `10.20.0.0/16`)
- **Control Plane Nodes**: `10.20.10.1` - `10.20.10.3`
- **LoadBalancer Pool**: `10.20.10.128` - `10.20.10.255` and `2a02:16a:2a0a:3::/112` (Cilium LB-IPAM, L2 + BGP)
- **Pod CIDRs**: `10.244.0.0/16`, `fd10:244::/56`
- **Service CIDRs**: `10.96.0.0/12`, `fd10:96::/112`

### Gateways

| Gateway | IP | Purpose |
|:--------|:---|:--------|
| envoy-external | 10.20.10.239 | Public traffic from the towonel tunnel (`external.wibrow.dev`) |
| envoy-internal | 10.20.10.238 | Home network and Tailscale traffic (`internal.wibrow.dev`) |

### Key Versions

| Component | Version | Source |
|:----------|:--------|:-------|
| Talos Linux | v1.14.0 | `talos/pitower/topf.yaml` |
| Kubernetes | v1.36.1 | `talos/pitower/topf.yaml` |
| Cilium | 1.20.2 | `kubernetes/apps/pitower/kube-system/cilium/operator/kustomization.yaml` |
| ArgoCD Helm chart | 10.9.6 | `kubernetes/bootstrap/kustomization.yaml` |
| app-template | 5.2.1 | `helmCharts` in each app's `kustomization.yaml` |
