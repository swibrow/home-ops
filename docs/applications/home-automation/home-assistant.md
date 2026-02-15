---
title: Home Assistant
---

# Home Assistant

[Home Assistant](https://www.home-assistant.io/) is the central smart home hub, integrating Zigbee devices (via Zigbee2MQTT and MQTT), Matter devices (via Matter Server), and Thread devices (via OTBR).

## Deployment Details

| Setting | Value |
|:--------|:------|
| **Image** | `ghcr.io/home-operations/home-assistant:2026.1.3` |
| **Namespace** | `home-automation` |
| **Gateway** | `envoy-external` (main UI), `envoy-internal` (code-server) |
| **URLs** | `ha.example.com` (UI), `ha-code.example.com` (code editor) |
| **Node** | `worker-04` (pinned) |
| **LoadBalancer IP** | `192.168.0.227` |

## Containers

Home Assistant runs as a multi-container pod with two containers:

### Main Application

The core Home Assistant container provides the web UI and automation engine:

```yaml
containers:
  app:
    image:
      repository: ghcr.io/home-operations/home-assistant
      tag: 2026.1.3
    resources:
      requests:
        cpu: 47m
        memory: 256Mi
      limits:
        memory: 2Gi
    securityContext:
      privileged: true
```

!!! warning "Privileged Mode"
    Home Assistant runs in privileged mode to support device discovery, mDNS, and direct hardware access. This is a known trade-off for full home automation functionality.

### Code Server Sidecar

A [code-server](https://github.com/coder/code-server) sidecar provides a VS Code editor for editing Home Assistant's YAML configuration files directly in the browser:

```yaml
containers:
  code-server:
    image:
      repository: ghcr.io/coder/code-server
      tag: "4.108.2"
    args:
      - --auth
      - none
      - --disable-telemetry
      - --disable-update-check
      - --user-data-dir
      - /config/.code-server
      - --extensions-dir
      - /config/.code-server
      - --port
      - "12321"
      - /config
    env:
      HASS_SERVER: http://localhost:8123
```

## Routing

Home Assistant has two HTTPRoutes:

| Route | Hostname | Gateway | Port | Purpose |
|:------|:---------|:--------|:-----|:--------|
| `app` | `ha.example.com` | `envoy-external` | 8123 | Main UI (public access) |
| `code` | `ha-code.example.com` | `envoy-internal` | 12321 | Code editor (LAN only) |

```yaml title="Route configuration"
route:
  app:
    hostnames:
      - ha.example.com
    parentRefs:
      - name: envoy-external
        namespace: networking
        sectionName: https
    rules:
      - backendRefs:
          - identifier: app
            port: 8123
  code:
    hostnames:
      - ha-code.example.com
    parentRefs:
      - name: envoy-internal
        namespace: networking
        sectionName: https
    rules:
      - backendRefs:
          - identifier: app
            port: 12321
```

## Service

The service is a LoadBalancer type with a dedicated Cilium LBIPAM IP, enabling direct LAN access and device discovery:

```yaml
service:
  app:
    controller: home-assistant
    type: LoadBalancer
    annotations:
      lbipam.cilium.io/ips: 192.168.0.227
    ports:
      http:
        port: 8123
      code-server:
        port: 12321
```

## Storage

| Mount | Source | Purpose |
|:------|:-------|:--------|
| `/config` | PVC `home-assistant-config` | All HA configuration, automations, database |
| `/tmp` | `emptyDir` (subpath `hass-tmp`) | Temporary files |

Both the main container and code-server sidecar share the `/config` PVC, allowing the code editor to modify configuration files that Home Assistant reads.

## Secrets

Sensitive configuration values (API keys, tokens) are injected from the `home-assistant-secret` ExternalSecret:

```yaml
envFrom:
  - secretRef:
      name: home-assistant-secret
```

## Integration Points

| Integration | Protocol | Endpoint |
|:------------|:---------|:---------|
| Zigbee2MQTT | MQTT via Mosquitto | `mqtt://mosquitto.home-automation.svc.cluster.local:1883` |
| Matter Server | WebSocket | `ws://localhost:5580` (co-located on same node) |
| OTBR | REST API | `http://otbr.home-automation.svc.cluster.local:8081` |
