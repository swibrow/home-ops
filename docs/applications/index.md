---
title: Applications
---

# Applications

The cluster runs a wide range of self-hosted applications, organized by category. Most applications are deployed using the [bjw-s app-template](https://github.com/bjw-s-labs/helm-charts) Helm chart (v4.6.2) and connect to one of two [Envoy Gateways](../networking/envoy-gateway.md) via Gateway API `HTTPRoute` resources.

## Application Categories

| Category | Apps | Namespace | Description |
|:---------|:----:|:----------|:------------|
| [Media Stack](media-stack/index.md) | 7 | `media` | Jellyfin media server, *arr apps for library management, and download clients |
| [Home Automation](home-automation/index.md) | 5 | `home-automation` | Home Assistant, Zigbee/Matter/Thread device management, MQTT broker |
| [Self-Hosted](selfhosted/index.md) | 12 | `selfhosted` | Dashboards, productivity tools, DNS utilities, and more |
| [Databases](databases/index.md) | -- | `cloudnative-pg` | CloudNative-PG PostgreSQL operator, clusters, and credential management |
| AI | 1 | `ai` | kagent -- Kubernetes-native AI agent framework |
| Banking | 2 | `banking` | Firefly III personal finance manager and data importer |

## Gateway Routing Pattern

All applications expose their web interfaces through `HTTPRoute` resources that attach to one of two Envoy Gateways:

| Gateway | IP | Target Domain | Use Case |
|:--------|:---|:--------------|:---------|
| `envoy-external` | 192.168.0.239 | `external.example.com` | Public services via Cloudflare tunnel |
| `envoy-internal` | 192.168.0.238 | `internal.example.com` | LAN / Tailscale VPN only |

```yaml title="Typical HTTPRoute attachment"
route:
  app:
    enabled: true
    hostnames:
      - app-name.example.com
    parentRefs:
      - name: envoy-external  # or envoy-internal
        namespace: networking
        sectionName: https
```

!!! info "App Template Helm Chart"
    The bjw-s app-template chart provides a standardized way to define controllers, services, routes, and persistence. Each application's `values.yaml` follows the same structure, making it straightforward to add new services. See [Development > App Template](../development/app-template.md) for the full pattern.

## Helm Chart Versions

| Chart | Version | Source |
|:------|:--------|:-------|
| bjw-s app-template | v4.6.2 | `ghcr.io/bjw-s-labs/helm` |
| CloudNative-PG | Latest | `cloudnative-pg.io` |
| kagent | 0.6.19 | `kagent.dev` |

## Common Patterns

### Stakater Reloader

Most controllers carry the annotation `reloader.stakater.com/auto: "true"`, which triggers automatic pod restarts when referenced ConfigMaps or Secrets change.

### Security Contexts

Applications follow a least-privilege model where possible:

```yaml
securityContext:
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true
  capabilities:
    drop:
      - ALL
```

### NFS Media Storage

Media applications mount the Synology NAS via NFS:

```yaml
persistence:
  media:
    type: nfs
    server: data
    path: /volume1/media
    globalMounts:
      - path: /data/nas-media
```

### External Secrets

Applications that need database credentials or API keys use `ExternalSecret` resources backed by the `cnpg-secrets` ClusterSecretStore or 1Password Connect.
