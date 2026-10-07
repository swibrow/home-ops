---
title: Home Assistant
---

# Home Assistant

[Home Assistant](https://www.home-assistant.io/) is the central smart home hub. It runs as **Home Assistant OS** on a Raspberry Pi 4 with the official PoE HAT, not in Kubernetes. The cluster only publishes it through Envoy Gateway at `ha.wibrow.dev`.

## Deployment Details

| Setting | Value |
|:--------|:------|
| **Host** | Home Assistant OS on a Raspberry Pi 4 |
| **Network** | IoT VLAN 101, `10.101.13.61` (DHCP reservation `homeassistant` in `terraform/unifi/reservations.tf`) |
| **DNS name** | `homeassistant.iot` |
| **Public URL** | `ha.wibrow.dev` on `envoy-external` |
| **In-cluster manifests** | `kubernetes/apps/pitower/home-automation/home-assistant/` |

## Routing

The app directory contains no workload, only an Envoy Gateway `Backend` that points at the HAOS host and an `HTTPRoute` that uses it:

```yaml title="service.yaml"
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: Backend
metadata:
  name: home-assistant
  namespace: home-automation
spec:
  endpoints:
    - fqdn:
        hostname: homeassistant.iot
        port: 8123
```

```yaml title="httproute.yaml"
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: home-assistant
  namespace: home-automation
spec:
  hostnames:
    - ha.wibrow.dev
  parentRefs:
    - name: envoy-external
      namespace: networking
      sectionName: https
  rules:
    - backendRefs:
        - group: gateway.envoyproxy.io
          kind: Backend
          name: home-assistant
          port: 8123
```

> [!WARNING]
> **The reservation is load-bearing**
>
> The Backend resolves `homeassistant.iot`, Frigate's MQTT config points at it, and `iot/button-plus/office-device-config.json` hardcodes the address as its MQTT broker. Change the DHCP reservation and these all need to follow.

## Integration Points

| Integration | Direction | Endpoint |
|:------------|:----------|:---------|
| Frigate | Frigate publishes events over MQTT | `homeassistant.iot:1883` |
| ToolHive MCP | An MCP server in the `ai` namespace talks to Home Assistant | `kubernetes/apps/pitower/ai/toolhive/toolhive-config/mcpserver-home-assistant.yaml` |
| Monitoring | Blackbox ICMP probe | `kubernetes/apps/pitower/monitoring/blackbox-exporter/probe-icmp.yaml` |

## Configuration as Code

Automations and device configs that are kept in Git live under `iot/`:

| Path | Contents |
|:-----|:---------|
| `iot/homeassistant/blueprints/` | Automation blueprints (e.g. Aqara H2 rocker switches) |
| `iot/homeassistant/dashboards/`, `packages/` | Dashboards and HA packages |
| `iot/esphome/devices/` | ESPHome device configs |
| `iot/button-plus/` | Button+ device config |

The HAOS host itself (PoE fan thresholds, the move onto VLAN 101) is managed with Ansible; see the `homeassistant` runbook in `ansible/README.md`.
