---
title: Node Management
---

# Node Management

Day-to-day operations for managing Talos nodes in the cluster. All commands use `just` recipes defined in `pitower/talos/justfile` or direct `talosctl` commands.

## Applying Configuration Changes

### Full Regeneration

When patches or secrets change, regenerate and reapply all configs:

```bash
cd pitower/talos
just config       # Regenerate base configs from secrets + patches
just patch        # Apply per-node patches
just apply-controlplanes   # Push configs to control plane nodes
just apply-workers         # Push configs to worker nodes
```

!!! tip "Config Apply is Non-Disruptive (Usually)"
    Most config changes are applied live without a reboot. Talos will indicate if a reboot is required after applying.

### Single Node Apply

To apply configuration to a single worker by name:

```bash
just apply-worker 04        # Applies to worker-04
just apply-worker pi-01     # Applies to worker-pi-01
```

This recipe dynamically resolves the node's IP from Talos member information:

```bash
talosctl get members -o json | jq -rs \
  --arg h "worker-<name>" \
  '[.[] | select(.spec.hostname == $h) | .spec.addresses[0]][0]'
```

### Control Plane Nodes Individually

For individual control plane nodes, use `talosctl` directly:

```bash
talosctl apply-config \
    --endpoints 192.168.0.201 \
    --nodes 192.168.0.201 \
    --file clusterconfig/worker-01.yaml
```

## Rebooting Nodes

!!! danger "Reboot Order Matters"
    Always reboot nodes **sequentially** with `--wait` to maintain cluster availability. Never reboot all control plane nodes simultaneously.

### Control Plane Nodes

```bash
just reboot-controlplanes
```

Reboots each control plane node one at a time, waiting for each to come back before proceeding:

```bash
for i in 1 2 3; do
    talosctl reboot \
        --endpoints "192.168.0.20${i}" \
        --nodes "192.168.0.20${i}" \
        --wait
done
```

### Worker Nodes

```bash
just reboot-workers
```

Reboots worker nodes sequentially:

```bash
for i in 1 2 3 4; do
    talosctl reboot --nodes "192.168.0.21${i}" --wait
done
```

!!! note
    The worker reboot recipe currently covers `192.168.0.211-214`. Adjust the loop if the worker node set changes.

## Resetting Nodes

To wipe and reset a node (for reprovisioning or troubleshooting):

```bash
just reset 04       # Resets 192.168.0.204
just reset 11       # Resets 192.168.0.211
```

This runs:

```bash
talosctl reset \
    --system-labels-to-wipe=EPHEMERAL \
    --system-labels-to-wipe=META \
    --reboot \
    --graceful=false \
    -n 192.168.0.2<suffix>
```

| Flag | Purpose |
|------|---------|
| `--system-labels-to-wipe=EPHEMERAL` | Wipes the ephemeral partition (kubelet data, pod storage) |
| `--system-labels-to-wipe=META` | Wipes the META partition (machine config, state) |
| `--reboot` | Reboots the node after reset |
| `--graceful=false` | Skips graceful shutdown (forces immediate reset) |

!!! danger "Destructive Operation"
    Reset wipes node state completely. The node will return to maintenance mode and need its config reapplied. For control plane nodes, ensure the remaining control plane has quorum before resetting.

## Upgrading Nodes

Upgrades swap the Talos OS image atomically. Each node type uses a different factory image with the appropriate extensions baked in.

### Upgrade Flow

```mermaid
flowchart LR
    A[New Talos Version<br/>Released] --> B[Update Image<br/>Variables in justfile]
    B --> C[Upgrade Control Plane<br/>Nodes Sequentially]
    C --> D[Upgrade Intel Workers<br/>Sequentially]
    D --> E[Upgrade RPi Workers<br/>Sequentially]
    E --> F[Verify Cluster<br/>Health]
```

### Control Plane Nodes (ARM/RPi)

```bash
just upgrade-controlplanes
```

```bash
for i in 1 2 3; do
    talosctl upgrade \
        --image factory.talos.dev/installer/de94b242...:v1.12.4 \
        --nodes "192.168.0.20${i}" \
        --preserve \
        --wait
done
```

### Control Plane Nodes (AMD)

```bash
just upgrade-controlplanes-amd
```

Uses the AMD-specific factory image for AMD-based control plane nodes.

### Intel Workers

```bash
just upgrade-workers-intel
```

```bash
for i in 4; do
    talosctl upgrade \
        --image factory.talos.dev/installer/97bf8e92...:v1.12.4 \
        --nodes "192.168.0.20${i}" \
        --preserve \
        --wait
done
```

### Raspberry Pi Workers

```bash
just upgrade-workers-rpi
```

```bash
for i in 1 2 3; do
    talosctl upgrade \
        --image factory.talos.dev/installer/a862538d...:v1.12.4 \
        --nodes "192.168.0.21${i}" \
        --preserve \
        --wait
done
```

!!! info "The `--preserve` Flag"
    All upgrade recipes use `--preserve` to retain the ephemeral partition across upgrades. This avoids re-downloading container images and preserves local state.

### Updating Image Variables

When upgrading to a new Talos version, update the image variables at the top of `pitower/talos/justfile`:

```just
cp_image := "factory.talos.dev/installer/<SCHEMATIC_ID>:<NEW_VERSION>"
cp_amd_image := "factory.talos.dev/installer/<SCHEMATIC_ID>:<NEW_VERSION>"
worker_intel_image := "factory.talos.dev/installer/<SCHEMATIC_ID>:<NEW_VERSION>"
worker_rpi_image := "factory.talos.dev/installer/<SCHEMATIC_ID>:<NEW_VERSION>"
```

If extensions have changed, regenerate schematic IDs first:

```bash
just image-id
```

## Image Management

### List Images on a Node

View all container images on a specific node, sorted by size:

```bash
just image-list 192.168.0.201
```

This runs:

```bash
talosctl -n <node> image list | sort -k4 -h
```

### Image Usage Across Nodes

Get a summary of image count and disk usage for all control plane and worker nodes:

```bash
just image-usage
```

Example output:

```
192.168.0.201       142 images  3.2 GB
192.168.0.202       138 images  3.1 GB
192.168.0.203       145 images  3.4 GB
192.168.0.204       112 images  2.8 GB
```

This iterates over all nodes defined in the `nodes` variable and reports containerd storage usage.

## Node-Specific Patches

Each node has a dedicated patch file under `pitower/talos/patches/nodes/`:

```
patches/nodes/
  worker-01.patch      # CP node 1 (Lenovo 440p, AMD)
  worker-02.patch      # CP node 2 (Lenovo 440p, AMD)
  worker-03.patch      # CP node 3 (Acemagician AM06, AMD)
  worker-04.patch      # Worker (Acemagician AM06, Intel)
  worker-05.patch      # Worker (Acemagician AM06, Intel)
  worker-06.patch      # Worker (Acemagician AM06, Intel)
  worker-pi-01.patch   # Worker (Raspberry Pi 4)
  worker-pi-02.patch   # Worker (Raspberry Pi 4)
  worker-pi-03.patch   # Worker (Raspberry Pi 4)
```

### What Node Patches Configure

| Field | Control Plane Nodes | Intel Workers | RPi Workers |
|-------|-------------------|---------------|-------------|
| `hostname` | Yes | Yes | Yes |
| `install.image` | Factory image (AMD) | Factory image (Intel) | Factory image (RPi PoE) |
| `install.disk` | -- | `/dev/mmcblk0` (where applicable) | -- |
| `network.interfaces` | DHCP + VIP (`192.168.0.200`) | Default | DHCP |
| `install.extraKernelArgs` | -- | -- | `initcall_blacklist=sensors_nct6683_init` |

### Editing a Node Patch

1. Edit the patch file (e.g., `patches/nodes/worker-04.patch`)
2. Regenerate configs: `just config && just patch`
3. Apply to the specific node: `just apply-worker 04`

!!! tip "VIP Assignment"
    The Kubernetes API VIP (`192.168.0.200`) is configured on all three control plane nodes via their per-node patches. Talos manages VIP failover automatically.

## Quick Reference

| Operation | Command |
|-----------|---------|
| Generate configs | `just config` |
| Patch per-node | `just patch` |
| Apply to all control planes | `just apply-controlplanes` |
| Apply to all workers | `just apply-workers` |
| Apply to single worker | `just apply-worker <name>` |
| Reboot control planes | `just reboot-controlplanes` |
| Reboot workers | `just reboot-workers` |
| Reset a node | `just reset <suffix>` |
| Upgrade control planes (RPi) | `just upgrade-controlplanes` |
| Upgrade control planes (AMD) | `just upgrade-controlplanes-amd` |
| Upgrade Intel workers | `just upgrade-workers-intel` |
| Upgrade RPi workers | `just upgrade-workers-rpi` |
| Build/apply addons | `just addons` |
| List images on node | `just image-list <node-ip>` |
| Image usage summary | `just image-usage` |
| Regenerate schematic IDs | `just image-id` |
