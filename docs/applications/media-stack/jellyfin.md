---
title: Jellyfin
---

# Jellyfin

[Jellyfin](https://jellyfin.org/) is the free and open-source media server that provides the playback interface for the entire media stack. It streams content organized by Sonarr and Radarr to any device with a web browser or native client.

## Deployment Details

| Setting | Value |
|:--------|:------|
| **Image** | `ghcr.io/jellyfin/jellyfin` (tag and digest pinned in `values.yaml`) |
| **Namespace** | `media` |
| **Gateway** | `envoy-external` |
| **URL** | `jellyfin.wibrow.dev` |
| **Node** | `worker-04` (pinned; tolerates the `dedicated=media-home:NoSchedule` taint) |
| **LoadBalancer IP** | `10.20.10.229` |

> [!NOTE]
> **Gateway Access**
>
> Jellyfin uses `envoy-external` for public access through the towonel tunnel. It also has a dedicated LoadBalancer IP (`10.20.10.229`) for direct LAN access, enabling native client discovery via DLNA or Jellyfin's UDP broadcast.

## GPU Transcoding

Jellyfin is configured for hardware-accelerated transcoding using Intel Quick Sync Video (QSV) on worker-04's Intel iGPU. The pod adds supplemental groups 44 and 109 (`video`, `render`) for `/dev/dri` access and runs as UID/GID 2000.

```yaml title="GPU resource allocation"
resources:
  requests:
    cpu: 10m
    gpu.intel.com/i915: 1
    memory: 320Mi
  limits:
    gpu.intel.com/i915: 1
    memory: 8192M
```

The node selector ensures Jellyfin runs on a node with an Intel GPU:

```yaml
nodeSelector:
  intel.feature.node.kubernetes.io/gpu: "true"
  kubernetes.io/arch: amd64
  kubernetes.io/hostname: "worker-04"
```

> [!NOTE]
> **Intel Device Plugins**
>
> The `intel-device-plugins` operator (`system/intel-device-plugins`) exposes `gpu.intel.com/i915` as a schedulable resource. worker-04, -05 and -06 carry the `intel.feature.node.kubernetes.io/gpu` label; the hostname selector pins Jellyfin to worker-04.

## Storage

Jellyfin uses these volumes:

| Mount | Source | Purpose |
|:------|:-------|:--------|
| `/config` | PVC `jellyfin` (10Gi, `pvc` component, backed up by `kopiur`) | Server configuration and database |
| `/config/metadata` | PVC `jellyfin-cache` (50Gi, `openebs-hostpath`, not backed up) | Metadata and image cache |
| `/data/nas-media` | NFS `data:/volume1/media` | Media library (Synology NAS) |
| `/cache`, `/config/log`, `/tmp` | `emptyDir` | Temporary files, logs |

```yaml title="NFS media mount"
persistence:
  media:
    type: nfs
    server: data
    path: /volume1/media
    advancedMounts:
      jellyfin:
        app:
          - path: /data/nas-media
```

## Configuration

### Environment Variables

| Variable | Value | Purpose |
|:---------|:------|:--------|
| `DOTNET_SYSTEM_IO_DISABLEFILELOCKING` | `true` | Prevents file locking issues on NFS volumes |
| `JELLYFIN_PublishedServerUrl` | `https://jellyfin.wibrow.dev` | URL advertised to clients |

### Service

Jellyfin is also exposed as a `LoadBalancer` service with a dedicated Cilium LBIPAM IP (`10.20.10.229`), allowing direct access from the LAN without going through Envoy Gateway. This enables native client discovery via DLNA or Jellyfin's UDP broadcast.

```yaml title="LoadBalancer service"
service:
  app:
    controller: jellyfin
    type: LoadBalancer
    annotations:
      lbipam.cilium.io/ips: "10.20.10.229"
    ports:
      http:
        port: 8096
```

## Route Configuration

```yaml title="HTTPRoute via envoy-external"
route:
  app:
    hostnames:
      - jellyfin.wibrow.dev
    parentRefs:
      - name: envoy-external
        namespace: networking
        sectionName: https
```
