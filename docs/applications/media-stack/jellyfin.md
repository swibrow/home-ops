---
title: Jellyfin
---

# Jellyfin

[Jellyfin](https://jellyfin.org/) is the free and open-source media server that provides the playback interface for the entire media stack. It streams content organized by Sonarr and Radarr to any device with a web browser or native client.

## Deployment Details

| Setting | Value |
|:--------|:------|
| **Image** | `ghcr.io/jellyfin/jellyfin:10.11.6` |
| **Namespace** | `media` |
| **Gateway** | `envoy-external` |
| **URL** | `jellyfin.example.com` |
| **Node** | `worker-04` (pinned) |
| **LoadBalancer IP** | `192.168.0.229` |

!!! info "Gateway Access"
    Jellyfin uses `envoy-external` for access via the Cloudflare tunnel. It also has a dedicated LoadBalancer IP (`192.168.0.229`) for direct LAN access, enabling native client discovery via DLNA or Jellyfin's UDP broadcast.

## GPU Transcoding

Jellyfin is configured for hardware-accelerated transcoding using Intel Quick Sync Video (QSV) on the Acemagician AM06 nodes, which have Intel iGPUs.

```yaml title="GPU resource allocation"
resources:
  requests:
    cpu: 100m
    gpu.intel.com/i915: 1
    memory: 1024M
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

!!! note "Intel Device Plugins"
    The `intel-device-plugins` operator runs in the cluster to expose `gpu.intel.com/i915` as a schedulable resource. This is deployed as part of the `kube-system` namespace.

## Storage

Jellyfin uses three persistent storage volumes:

| Mount | Source | Purpose |
|:------|:-------|:--------|
| `/config` | PVC `jellyfin` | Server configuration and database |
| `/config/metadata` | PVC `jellyfin-cache` | Metadata and image cache |
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

### Service

Jellyfin is also exposed as a `LoadBalancer` service with a dedicated Cilium LBIPAM IP (`192.168.0.229`), allowing direct access from the LAN without going through Envoy Gateway. This enables native client discovery via DLNA or Jellyfin's UDP broadcast.

```yaml title="LoadBalancer service"
service:
  app:
    controller: jellyfin
    type: LoadBalancer
    annotations:
      lbipam.cilium.io/ips: "192.168.0.229"
    ports:
      http:
        port: 8096
```

## Route Configuration

```yaml title="HTTPRoute via envoy-external"
route:
  app:
    hostnames:
      - jellyfin.example.com
    parentRefs:
      - name: envoy-external
        namespace: networking
        sectionName: https
```
