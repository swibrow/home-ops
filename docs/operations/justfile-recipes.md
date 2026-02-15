# Justfile Recipes

Complete reference for all justfile recipes in `pitower/talos/justfile`. Run recipes from the `pitower/talos/` directory with `just <recipe>`.

!!! tip "Running Recipes"
    ```bash
    cd pitower/talos
    just <recipe-name>
    ```

---

## Configuration Generation

Recipes for generating and patching Talos machine configurations from encrypted secrets and patch files.

| Recipe | Description |
|:-------|:------------|
| `config` | Generate Talos config from SOPS-encrypted secrets |
| `patch` | Patch machine configs for all nodes using per-node patches |

### `just config`

Decrypts `secrets.sops.yaml` with SOPS, then runs `talosctl gen config` to produce base control plane and worker configs in `clusterconfig/`.

```bash
just config
```

Internally runs:

```bash
sops -d ./secrets.sops.yaml > ./secrets.yaml
talosctl gen config \
    pitower \
    https://192.168.0.200:6443 \
    --with-secrets ./secrets.yaml \
    --with-examples=true \
    --config-patch-control-plane @patches/controlplane.patch \
    --config-patch @patches/general.patch \
    --output ./clusterconfig \
    --force
```

### `just patch`

Takes the base `controlplane.yaml` and `worker.yaml` from `clusterconfig/` and applies per-node patches to produce individual node configs.

```bash
just patch
```

This generates files like `worker-01.yaml`, `worker-04.yaml`, `worker-pi-01.yaml`, etc.

---

## Deployment

Recipes for applying configurations to nodes and bootstrapping the cluster.

| Recipe | Description |
|:-------|:------------|
| `bootstrap` | Bootstrap the Talos cluster (first-time setup) |
| `apply-controlplanes` | Apply configs to control plane nodes (192.168.0.201-203) |
| `apply-workers` | Apply configs to all worker nodes |
| `apply-worker <name>` | Apply config to a specific worker by name suffix |
| `addons` | Build and apply kustomize addons (CNI, kubelet-csr-approver) |

### `just bootstrap`

First-time cluster bootstrap. Bootstraps etcd on node 201 and fetches the kubeconfig.

```bash
just bootstrap
```

!!! warning "One-Time Operation"
    Only run `bootstrap` once during initial cluster setup. Running it again can corrupt the cluster.

### `just apply-controlplanes`

Applies machine configs to all three control plane nodes.

```bash
just apply-controlplanes
```

### `just apply-workers`

Applies machine configs to all worker nodes (Intel and Raspberry Pi).

```bash
just apply-workers
```

### `just apply-worker <name>`

Applies config to a single worker by name suffix. Automatically resolves the node's IP address from Talos member list.

```bash
# Apply to worker-04 (Intel)
just apply-worker 04

# Apply to worker-pi-01 (Raspberry Pi)
just apply-worker pi-01
```

### `just addons`

Builds kustomize addons with Helm support and applies them to the cluster. Used for CNI (Cilium) and kubelet-csr-approver during bootstrap.

```bash
just addons
```

---

## Reboot

Recipes for rebooting nodes sequentially with wait between each node.

| Recipe | Description |
|:-------|:------------|
| `reboot-controlplanes` | Reboot control plane nodes one at a time |
| `reboot-workers` | Reboot worker nodes one at a time |

### `just reboot-controlplanes`

Reboots control plane nodes 192.168.0.201 through 203 sequentially, waiting for each node to come back before rebooting the next.

```bash
just reboot-controlplanes
```

### `just reboot-workers`

Reboots worker nodes 192.168.0.211 through 214 sequentially with wait.

```bash
just reboot-workers
```

!!! note "Sequential Reboot"
    Both reboot recipes use `--wait` to ensure each node is fully back online before proceeding to the next. This maintains cluster availability throughout the process.

---

## Reset

| Recipe | Description |
|:-------|:------------|
| `reset <suffix>` | Reset a Talos node by its last IP octet |

### `just reset <suffix>`

Resets a node by wiping its ephemeral and meta partitions, then reboots. Use the last two digits of the node's IP address.

```bash
# Reset node at 192.168.0.204
just reset 04

# Reset node at 192.168.0.211
just reset 11
```

!!! danger "Destructive Operation"
    This wipes the node's ephemeral storage and metadata. The node will need to be re-joined to the cluster. Uses `--graceful=false` for a forced reset.

---

## Upgrade

Recipes for upgrading Talos on nodes, grouped by architecture. All upgrades use `--preserve` to retain ephemeral data and `--wait` for sequential processing.

| Recipe | Description |
|:-------|:------------|
| `upgrade-controlplanes` | Upgrade control plane nodes with ARM image |
| `upgrade-controlplanes-amd` | Upgrade control plane nodes with AMD image |
| `upgrade-workers-intel` | Upgrade Intel/AMD worker nodes |
| `upgrade-workers-rpi` | Upgrade Raspberry Pi worker nodes |

### `just upgrade-controlplanes`

Upgrades ARM-based control plane nodes (201-203) to the current Talos version.

```bash
just upgrade-controlplanes
```

### `just upgrade-controlplanes-amd`

Upgrades AMD-based control plane nodes (currently node 203 only).

```bash
just upgrade-controlplanes-amd
```

### `just upgrade-workers-intel`

Upgrades Intel/AMD worker nodes (currently node 204).

```bash
just upgrade-workers-intel
```

### `just upgrade-workers-rpi`

Upgrades Raspberry Pi worker nodes (211-213).

```bash
just upgrade-workers-rpi
```

!!! info "Factory Images"
    Each architecture uses a different factory image with tailored system extensions:

    - **ARM control plane**: includes base extensions for Pi 4
    - **AMD control plane**: includes AMD-specific extensions
    - **Intel worker**: includes Intel GPU and related extensions
    - **RPi worker**: includes RPi PoE hat extensions

---

## Diagnostics

Recipes for inspecting node images and disk usage.

| Recipe | Description |
|:-------|:------------|
| `image-list <node>` | List container images on a node sorted by size |
| `image-usage` | Show image count and disk usage per node |
| `image-id` | Print Talos factory image IDs from extension files |

### `just image-list <node>`

Lists all container images on a specific node, sorted by size (smallest first).

```bash
just image-list 192.168.0.201
```

### `just image-usage`

Shows a summary of image count and containerd disk usage for all nodes.

```bash
just image-usage
```

Example output:

```
192.168.0.201      87 images  2.1 GB
192.168.0.202      85 images  2.0 GB
192.168.0.203      92 images  2.4 GB
192.168.0.204     104 images  3.8 GB
```

### `just image-id`

Queries the Talos factory API to get schematic IDs for each architecture's extension file.

```bash
just image-id
```

Example output:

```
amd: f19ad7b4a5d29151f3a59ef2d9c581cf89e77142e52f0abb5022e8f0b95ad0b9
intel: 97bf8e92fc6bba0f03928b859c08295d7615737b29db06a97be51dc63004e403
rpi-poe: a862538d0862e8ad5b17fadc2b56599677101537b3f75926085d8cbff4a411b9
```

---

## Complete Recipe Summary

| Recipe | Arguments | Category |
|:-------|:----------|:---------|
| `config` | -- | Configuration |
| `patch` | -- | Configuration |
| `bootstrap` | -- | Deployment |
| `apply-controlplanes` | -- | Deployment |
| `apply-workers` | -- | Deployment |
| `apply-worker` | `<name>` (e.g., `04`, `pi-01`) | Deployment |
| `addons` | -- | Deployment |
| `reset` | `<suffix>` (last IP octet) | Reset |
| `reboot-controlplanes` | -- | Reboot |
| `reboot-workers` | -- | Reboot |
| `upgrade-controlplanes` | -- | Upgrade |
| `upgrade-controlplanes-amd` | -- | Upgrade |
| `upgrade-workers-intel` | -- | Upgrade |
| `upgrade-workers-rpi` | -- | Upgrade |
| `image-list` | `<node>` (IP address) | Diagnostics |
| `image-usage` | -- | Diagnostics |
| `image-id` | -- | Diagnostics |
