# IP Allocation

Complete IP address allocation and DNS record tables for the cluster.

---

## Node Addresses

| IP Address | Hostname | Role | Architecture |
|:-----------|:---------|:-----|:-------------|
| 192.168.0.200 | -- | Talos VIP (unused) | Virtual IP |
| 192.168.0.201 | worker-01 | Control Plane | ARM64 (Pi 4) |
| 192.168.0.202 | worker-02 | Control Plane | ARM64 (Pi 4) |
| 192.168.0.203 | worker-03 | Control Plane | AMD64 |
| 192.168.0.204 | worker-04 | Worker (Intel) | AMD64 |
| 192.168.0.211 | worker-pi-01 | Worker (Pi) | ARM64 |
| 192.168.0.212 | worker-pi-02 | Worker (Pi) | ARM64 |
| 192.168.0.213 | worker-pi-03 | Worker (Pi) | ARM64 |

---

## LoadBalancer IP Pool

The Cilium LBIPAM pool allocates LoadBalancer service IPs from the range `192.168.0.220-239`.

| IP Address | Service | Type |
|:-----------|:--------|:-----|
| 192.168.0.220-237 | Available | Cilium LBIPAM Pool |
| 192.168.0.238 | envoy-internal | Gateway |
| 192.168.0.239 | envoy-external | Gateway |

### Gateway Details

| Gateway | IP | Target Domain | Purpose |
|:--------|:---|:-------------|:--------|
| envoy-external | 192.168.0.239 | external.example.com | Receives traffic from Cloudflare tunnel via nginx |
| envoy-internal | 192.168.0.238 | internal.example.com | Receives traffic from LAN and Tailscale VPN |

---

## Network Diagram

```mermaid
flowchart TB
    subgraph Internet
        CF[Cloudflare<br/>*.example.com]
    end

    subgraph Router["Ubiquiti Router"]
        DHCP[DHCP / DNS]
    end

    subgraph Cluster["Cluster (192.168.0.0/24)"]
        subgraph ControlPlane["Control Plane"]
            CP1[192.168.0.201<br/>worker-01]
            CP2[192.168.0.202<br/>worker-02]
            CP3[192.168.0.203<br/>worker-03]
        end
        subgraph Workers["Workers"]
            W4[192.168.0.204<br/>worker-04]
            WP1[192.168.0.211<br/>worker-pi-01]
            WP2[192.168.0.212<br/>worker-pi-02]
            WP3[192.168.0.213<br/>worker-pi-03]
        end
        subgraph LB["LoadBalancers (Cilium L2)"]
            EE[192.168.0.239<br/>envoy-external]
            EI[192.168.0.238<br/>envoy-internal]
        end
    end

    CF -->|Tunnel| EE
    DHCP --> ControlPlane
    DHCP --> Workers
```

---

## DNS Records

### Cloudflare-Managed Records

| Record | Type | Target | Proxied | Purpose |
|:-------|:-----|:-------|:--------|:--------|
| `*.example.com` | CNAME | `external.example.com` | Yes | Wildcard for all services |
| `external.example.com` | CNAME | `<tunnel-id>.cfargotunnel.com` | Yes | Cloudflare tunnel endpoint |
| `internal.example.com` | A | `192.168.0.238` | No | Internal gateway |

### Traffic Flow by Record

```mermaid
flowchart LR
    subgraph External["External Access"]
        W1["*.example.com"] -->|CNAME| E1["external.example.com"]
        E1 -->|CNAME| T1["tunnel.cfargotunnel.com"]
        T1 -->|Tunnel| N1[nginx]
        N1 --> EE1[envoy-external<br/>192.168.0.239]
    end

    subgraph Internal["Internal Access"]
        W3["internal.example.com"] -->|A record| EI1[envoy-internal<br/>192.168.0.238]
    end
```

---

## Address Space Summary

| Range | Purpose | Count |
|:------|:--------|:------|
| 192.168.0.200 | Talos VIP | 1 |
| 192.168.0.201-203 | Control plane nodes | 3 |
| 192.168.0.204 | Intel/AMD worker | 1 |
| 192.168.0.205-210 | Reserved (future workers) | 6 |
| 192.168.0.211-213 | Raspberry Pi workers | 3 |
| 192.168.0.214-219 | Reserved (future Pi workers) | 6 |
| 192.168.0.220-239 | Cilium LBIPAM pool | 20 |

!!! note "DNS Interception"
    The Ubiquiti router intercepts all DNS traffic on port 53. To verify actual Cloudflare DNS records, use DNS over HTTPS (DoH):
    ```bash
    curl -sH 'accept: application/dns-json' \
      'https://cloudflare-dns.com/dns-query?name=echo.example.com&type=A' | jq
    ```
