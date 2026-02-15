# App Catalog

Complete catalog of all applications deployed in the cluster, organized by category.

---

## Summary

| Category | App Count |
|:---------|:---------:|
| [AI](#ai) | 1 |
| [Banking](#banking) | 2 |
| [Cert-Manager](#cert-manager) | 2 |
| [CloudNativePG](#cloudnativepg) | 3 |
| [Home Automation](#home-automation) | 5 |
| [Kube-System](#kube-system) | 3 |
| [Media](#media) | 7 |
| [Monitoring](#monitoring) | 4 |
| [Networking](#networking) | 6 |
| [OpenEBS](#openebs) | 1 |
| [Rook Ceph](#rook-ceph) | 3 |
| [Security](#security) | 5 |
| [Self-Hosted](#self-hosted) | 12 |
| [System](#system) | 6 |
| **Total** | **60** |

---

## AI

| Name | Chart/Image | Gateway | URL | Description |
|:-----|:------------|:--------|:----|:------------|
| kagent | app-template | -- | -- | AI agent workload |

---

## Banking

| Name | Chart/Image | Gateway | URL | Description |
|:-----|:------------|:--------|:----|:------------|
| firefly | app-template | external | `firefly.example.com` | Firefly III personal finance manager |
| firefly-importer | app-template | external | `firefly-importer.example.com` | Data importer for Firefly III |

---

## Cert-Manager

| Name | Chart/Image | Gateway | URL | Description |
|:-----|:------------|:--------|:----|:------------|
| cert-manager | cert-manager (Helm) | -- | -- | X.509 certificate management for Kubernetes |
| issuers | Kustomize manifests | -- | -- | ClusterIssuer resources for Let's Encrypt |

---

## CloudNativePG

| Name | Chart/Image | Gateway | URL | Description |
|:-----|:------------|:--------|:----|:------------|
| operator | cloudnative-pg (Helm) | -- | -- | CloudNativePG operator for PostgreSQL |
| cluster | Kustomize manifests | -- | -- | PostgreSQL cluster instance |
| clustersecretstore | Kustomize manifests | -- | -- | Secret store for database credentials |

---

## Home Automation

| Name | Chart/Image | Gateway | URL | Description |
|:-----|:------------|:--------|:----|:------------|
| home-assistant | app-template | external | `hass.example.com` | Home automation platform |
| matter-server | app-template | -- | -- | Matter protocol server for smart home devices |
| mosquitto | app-template | -- | -- | MQTT broker for IoT messaging |
| otbr | app-template | -- | -- | OpenThread Border Router for Thread devices |
| zigbee2mqtt | app-template | external | `z2m.example.com` | Zigbee to MQTT bridge |

---

## Kube-System

| Name | Chart/Image | Gateway | URL | Description |
|:-----|:------------|:--------|:----|:------------|
| cilium | cilium (Helm) | -- | -- | eBPF-based CNI with L2 announcements, DSR, Maglev |
| coredns | coredns (Helm) | -- | -- | Cluster DNS server |
| metrics-server | metrics-server (Helm) | -- | -- | Resource metrics for HPA and kubectl top |

---

## Media

| Name | Chart/Image | Gateway | URL | Description |
|:-----|:------------|:--------|:----|:------------|
| autobrr | app-template | external | `autobrr.example.com` | Automation for torrent/usenet indexers |
| jellyfin | app-template | external | `jellyfin.example.com` | Open-source media server |
| prowlarr | app-template | external | `prowlarr.example.com` | Indexer manager for Sonarr/Radarr |
| qbittorrent | app-template | external | `qbit.example.com` | BitTorrent client |
| radarr | app-template | external | `radarr.example.com` | Movie collection manager |
| sabnzbd | app-template | external | `sabnzbd.example.com` | Usenet download client |
| sonarr | app-template | external | `sonarr.example.com` | TV series collection manager |

---

## Monitoring

| Name | Chart/Image | Gateway | URL | Description |
|:-----|:------------|:--------|:----|:------------|
| fluent-bit | fluent-bit (Helm) | -- | -- | Log collector and forwarder |
| grafana | grafana (Helm) | external | `grafana.example.com` | Metrics visualization and dashboards |
| kube-prometheus-stack | kube-prometheus-stack (Helm) | external | `prometheus.example.com` | Prometheus, Alertmanager, and node exporters |
| loki | loki (Helm) | -- | -- | Log aggregation system |

---

## Networking

| Name | Chart/Image | Gateway | URL | Description |
|:-----|:------------|:--------|:----|:------------|
| cloudflared | app-template | -- | -- | Cloudflare tunnel for secure external access |
| envoy-gateway | envoy-gateway (Helm) | -- | -- | Gateway API implementation (2 gateways) |
| external-dns | external-dns (Helm) | -- | -- | Automated DNS record management |
| nginx | nginx (Helm) | -- | -- | Reverse proxy (external + internal) |
| openspeedtest | app-template | internal | `speedtest.example.com` | Network speed test tool |
| tailscale | tailscale (Helm) | -- | -- | VPN mesh for remote access |

---

## OpenEBS

| Name | Chart/Image | Gateway | URL | Description |
|:-----|:------------|:--------|:----|:------------|
| openebs | openebs (Helm) | -- | -- | Local persistent volume provisioner |

---

## Rook Ceph

| Name | Chart/Image | Gateway | URL | Description |
|:-----|:------------|:--------|:----|:------------|
| operator | rook-ceph (Helm) | -- | -- | Rook Ceph operator for distributed storage |
| cluster | Kustomize manifests | -- | -- | Ceph cluster configuration |
| add-ons | Kustomize manifests | external | `ceph.example.com` | Dashboard and toolbox |

---

## Security

| Name | Chart/Image | Gateway | URL | Description |
|:-----|:------------|:--------|:----|:------------|
| 1password-connect | app-template | -- | -- | 1Password Connect server for External Secrets |
| authelia | app-template | external | `auth.example.com` | SSO and 2FA authentication portal |
| aws-identity-webhook | Kustomize manifests | -- | -- | AWS IAM identity webhook |
| external-secrets | external-secrets (Helm) | -- | -- | Operator for syncing external secrets |
| lldap | app-template | external | `lldap.example.com` | Lightweight LDAP directory |

---

## Self-Hosted

| Name | Chart/Image | Gateway | URL | Description |
|:-----|:------------|:--------|:----|:------------|
| cryptgeon | app-template | external | `cryptgeon.example.com` | Encrypted secret sharing |
| echo-server | app-template | external | `echo.example.com` | HTTP echo server for testing |
| excalidraw | app-template | external | `draw.example.com` | Collaborative whiteboard |
| glance | app-template | external | `glance.example.com` | Dashboard / start page |
| homepage | app-template | external | `home.example.com` | Application dashboard |
| house-hunter | app-template | external | `house.example.com` | Property search aggregator |
| miniflux | app-template | external | `rss.example.com` | Minimalist RSS reader |
| n8n | app-template | external | `n8n.example.com` | Workflow automation platform |
| rrda | app-template | external | `rrda.example.com` | DNS lookup API |
| sharkord | app-template | external | `sharkord.example.com` | Custom application |
| tandoor | app-template | external | `recipes.example.com` | Recipe manager |
| whoami | app-template | external | `whoami.example.com` | Simple HTTP request echo |

---

## System

| Name | Chart/Image | Gateway | URL | Description |
|:-----|:------------|:--------|:----|:------------|
| intel-device-plugins | Kustomize manifests | -- | -- | Intel GPU device plugin and operator |
| kubelet-csr-approver | kubelet-csr-approver (Helm) | -- | -- | Automatic CSR approval for kubelets |
| node-feature-discovery | node-feature-discovery (Helm) | -- | -- | Hardware feature detection and labeling |
| reloader | reloader (Helm) | -- | -- | Auto-restart pods on ConfigMap/Secret changes |
| snapshot-controller | snapshot-controller (Helm) | -- | -- | Volume snapshot controller |
| volsync | volsync (Helm) | -- | -- | Persistent volume replication and backup |

---

## Gateway Distribution

| Gateway | Count | Services |
|:--------|:-----:|:---------|
| envoy-external | ~26 | Most user-facing apps |
| envoy-internal | ~2 | Internal tools (speedtest, etc.) |
| None | ~32 | Infrastructure, operators, system services |

---

## Chart Distribution

| Chart Type | Count | Description |
|:-----------|:-----:|:------------|
| app-template (bjw-s) | ~30 | Standard application deployment |
| Dedicated Helm chart | ~15 | Infrastructure components with their own charts |
| Kustomize manifests | ~15 | CRDs, operators, and custom resources |
