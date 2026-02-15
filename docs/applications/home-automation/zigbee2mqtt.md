---
title: Zigbee2MQTT
---

# Zigbee2MQTT

[Zigbee2MQTT](https://www.zigbee2mqtt.io/) bridges Zigbee devices to MQTT, allowing Home Assistant and other consumers to interact with Zigbee sensors, switches, and lights through the Mosquitto MQTT broker.

## Deployment Details

| Setting | Value |
|:--------|:------|
| **Image** | `ghcr.io/koenkk/zigbee2mqtt:2.8.0` |
| **Namespace** | `home-automation` |
| **Gateway** | `envoy-internal` |
| **URL** | `zigbee.example.com` |
| **Node** | `worker-04` (pinned) |

## Zigbee Coordinator

Zigbee2MQTT connects to an **SLZB-06** network-attached Zigbee coordinator over TCP:

```yaml
env:
  ZIGBEE2MQTT_CONFIG_SERIAL_PORT: tcp://slzb-06:6638
  ZIGBEE2MQTT_CONFIG_SERIAL_ADAPTER: zstack
  ZIGBEE2MQTT_CONFIG_SERIAL_BAUDRATE: 115200
```

!!! tip "Network vs USB"
    The SLZB-06 is a network-based coordinator, so there is no need for USB device passthrough (`/dev/ttyACM0`). This simplifies the Kubernetes deployment and removes host device dependencies. The commented-out USB hostPath mount in `values.yaml` is kept for reference.

## MQTT Integration

Zigbee2MQTT publishes device state to and receives commands from the Mosquitto MQTT broker:

```yaml title="MQTT configuration"
env:
  ZIGBEE2MQTT_CONFIG_MQTT_SERVER: mqtt://mosquitto.home-automation.svc.cluster.local
  ZIGBEE2MQTT_CONFIG_MQTT_VERSION: 5
  ZIGBEE2MQTT_CONFIG_MQTT_KEEPALIVE: 60
  ZIGBEE2MQTT_CONFIG_MQTT_REJECT_UNAUTHORIZED: false
  ZIGBEE2MQTT_CONFIG_MQTT_INCLUDE_DEVICE_INFORMATION: true
```

### Home Assistant Discovery

Zigbee2MQTT is configured to publish Home Assistant MQTT discovery messages, enabling automatic device registration:

```yaml
env:
  ZIGBEE2MQTT_CONFIG_HOMEASSISTANT_ENABLED: true
  ZIGBEE2MQTT_CONFIG_HOMEASSISTANT_DISCOVERY_TOPIC: homeassistant
  ZIGBEE2MQTT_CONFIG_HOMEASSISTANT_STATUS_TOPIC: homeassistant/status
  ZIGBEE2MQTT_CONFIG_HOMEASSISTANT_EXPERIMENTAL_EVENT_ENTITIES: true
```

## Containers

Like Home Assistant, Zigbee2MQTT runs as a multi-container pod with a code-server sidecar:

### Main Application

```yaml
containers:
  app:
    image:
      repository: ghcr.io/koenkk/zigbee2mqtt
      tag: 2.8.0
    securityContext:
      privileged: true
```

### Code Server Sidecar

The code-server sidecar at port 12321 provides direct access to Zigbee2MQTT's data files:

```yaml
containers:
  code-server:
    image:
      repository: ghcr.io/coder/code-server
      tag: 4.108.2
    args:
      - --auth
      - none
      - --port
      - "12321"
      - /data
```

## Routing

The HTTPRoute uses path-based routing to split traffic between the Zigbee2MQTT frontend and code-server:

```yaml title="Path-based routing"
route:
  app:
    hostnames:
      - zigbee.example.com
    parentRefs:
      - name: envoy-internal
        namespace: networking
        sectionName: https
    rules:
      - matches:
          - path:
              type: PathPrefix
              value: /code
        backendRefs:
          - identifier: app
            port: 12321
        filters:
          - type: URLRewrite
            urlRewrite:
              path:
                type: ReplacePrefixMatch
                replacePrefixMatch: /
      - backendRefs:
          - identifier: app
            port: 8080
```

| Path | Backend | Description |
|:-----|:--------|:------------|
| `/code/*` | code-server (12321) | VS Code editor (path rewritten to `/`) |
| `/*` | Zigbee2MQTT (8080) | Zigbee2MQTT web frontend |

## Storage

| Mount | Source | Purpose |
|:------|:-------|:--------|
| `/data` | PVC `zigbee2mqtt` | Configuration, device database, coordinator backup |

Both the main container and code-server share the `/data` PVC.

## Key Configuration

| Setting | Value | Purpose |
|:--------|:------|:--------|
| `TZ` | `Europe/Zurich` | Timezone for timestamps |
| `PERMIT_JOIN` | `true` | Allow new devices to join the network |
| `FRONTEND_ENABLED` | `true` | Enable the web-based dashboard |
| `FRONTEND_PORT` | `8080` | Port for the web UI |
| `FRONTEND_URL` | `https://zigbee.example.com` | External URL for WebSocket connections |
| `LOG_LEVEL` | `info` | Logging verbosity |
| `DEVICE_OPTIONS_RETAIN` | `true` | Retain last device state in MQTT |
