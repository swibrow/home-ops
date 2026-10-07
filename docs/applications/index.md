---
title: Applications
---

# Applications

The cluster runs a wide range of self-hosted applications, organized by category under `kubernetes/apps/pitower/<category>/<app>/`. Each category is a namespace and each app directory is an ArgoCD Application named `pitower-<category>-<app>`. Most applications are deployed with the [bjw-s app-template](https://github.com/bjw-s-labs/helm-charts) Helm chart (5.2.1) and are reached through one of two [Envoy Gateways](../networking/envoy-gateway.md) via Gateway API `HTTPRoute` resources.

## Application Categories

| Category | Apps | Description |
|:---------|:----:|:------------|
| [Media Stack](media-stack/index.md) (`media`) | 8 | Jellyfin, Immich, *arr apps, autobrr, and download clients |
| [Home Automation](home-automation/index.md) (`home-automation`) | 2 | Frigate NVR, plus an ingress route to Home Assistant OS running outside the cluster |
| [Self-Hosted](selfhosted/index.md) (`selfhosted`) | 13 | Dashboards, productivity tools, and debugging utilities |
| [Databases](databases/index.md) (`database`) | 7 | CloudNative-PG operator, clusters and tenants, Dragonfly and ClickHouse operators |
| `ai` | 17 | Open WebUI, ComfyUI, LLMKube, agentgateway, ToolHive MCP servers, SearXNG, memini, MLflow, browser-use, and more |
| `analytics` | 1 | [Rybbit](https://insights.wibrow.dev) web analytics (backend, client, ClickHouse) |
| `banking` | 5 | Actual, Firefly III and its importer, Ghostfolio, Paperless |
| `dev` | 4 | Forgejo, dev-desktop, herdr, propagit |
| `second-brain` | 2 | AFFiNE and CouchDB (Obsidian sync) |
| `kubevirt` / `vms` | 2 / 3 | KubeVirt and CDI, and the VMs they run (dev, omarchy, debian-test) |
| `workflows` | 3 | Argo Workflows, Argo Events, agentgateway model sync |
| `workshop` | 1 | Bambuddy (Bambu Lab printer management) |
| `arc` | 2 | GitHub Actions Runner Controller and runner scale sets |
| `renovate` | 1 | renovate-operator |
| Platform | | `cert-manager`, `kopiur-system`, `kube-system`, `monitoring`, `networking`, `openebs`, `rook-ceph`, `security`, `system` |
| Projects | | Single-app categories for personal projects: `flickerd`, `garrison`, `goat`, `pantry-system`, `rackrat`, `trade-ops`, `trade-ops-dev` |

## Gateway Routing Pattern

Applications expose their web interfaces through `HTTPRoute` resources attached to one of two Envoy Gateways in the `networking` namespace:

| Gateway | LoadBalancer IP | DNS target | Use Case |
|:--------|:----------------|:-----------|:---------|
| `envoy-external` | `10.20.10.239` | `external.wibrow.dev` | Public services, reached through the towonel tunnel |
| `envoy-internal` | `10.20.10.238` | `internal.wibrow.dev` | LAN and Tailscale only |

```yaml title="Typical HTTPRoute attachment"
route:
  app:
    hostnames:
      - app-name.wibrow.dev
    parentRefs:
      - name: envoy-external  # or envoy-internal
        namespace: networking
        sectionName: https
```

The `ai` namespace also runs its own `agentgateway` Gateway for LLM and MCP traffic.

> [!NOTE]
> **App Template Helm Chart**
>
> The chart is pulled from `oci://ghcr.io/bjw-s-labs/helm` by each app's `kustomization.yaml` and kept current by Renovate. See [Development > App Template](../development/app-template.md) for the full pattern.

## Common Patterns

### Stakater Reloader

Controllers that consume Secrets or ConfigMaps carry `reloader.stakater.com/auto: "true"`, which restarts pods when those objects change.

### Single Sign-On

Apps that support OIDC authenticate against [Kanidm](https://kanidm.com/) at `idm.wibrow.dev`.

### Persistent Data and Backups

App data PVCs are declared with the `pvc` kustomize component and backed up hourly to Garage S3 by the `kopiur` component. See [Development > Adding Apps](../development/adding-apps.md#step-6-add-persistence-optional).

### NFS Media Storage

The *arr apps, the download clients, Jellyfin and Frigate mount the Synology NAS over NFS (server `data`):

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

Secrets come from `ExternalSecret` resources backed by the `infisical` ClusterSecretStore (paths `/<category>/<app>/<SECRET_NAME>`). Database credentials come from the `cnpg-secrets-database` ClusterSecretStore, usually through the `cnpg-db-shared` component.
