# Reference

Quick-reference tables and catalogs for the cluster.

---

## Sections

| Page | Description |
|:-----|:------------|
| [IP Allocation](ip-allocation.md) | Complete IP address allocation table and DNS records |
| [App Catalog](app-catalog.md) | Full catalog of all applications deployed in the cluster |

---

## Quick Links

### Network

- **Domain**: `example.com` (Cloudflare-managed)
- **Cluster VIP**: `192.168.0.200`
- **LoadBalancer Pool**: `192.168.0.220-239` (Cilium LBIPAM)
- **Control Plane Nodes**: `192.168.0.201-203`
- **Worker Nodes**: `192.168.0.204`, `192.168.0.211-213`

### Gateways

| Gateway | IP | Purpose |
|:--------|:---|:--------|
| envoy-external | 192.168.0.239 | Cloudflare tunnel traffic (`external.example.com`) |
| envoy-internal | 192.168.0.238 | Internal/VPN traffic (`internal.example.com`) |

### Key Versions

| Component | Version |
|:----------|:--------|
| Talos Linux | v1.12.4 |
| app-template | 4.6.2 |
