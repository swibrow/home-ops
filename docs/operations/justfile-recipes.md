# Justfile Recipes

Complete reference for the Talos justfile recipes. Lifecycle recipes are shared between clusters via `kubernetes/talos/shared/talos.justfile` and wrap [topf](https://github.com/postfinance/topf); diagnostics wrap `talosctl`.

!!! tip "Running Recipes"
    ```bash
    cd kubernetes/talos/pitower   # or pistack
    just <recipe-name>

    # or from the repo root via modules
    just pitower::<recipe-name>
    ```

---

## How It Works

topf reads `topf.yaml` in the cluster directory and assembles each node's machine config from layered strategic-merge patches:

```text
kubernetes/talos/pitower/
├── topf.yaml              # cluster identity, nodes, versions, schematics
├── secrets.sops.yaml      # SOPS-encrypted secrets bundle (decrypted by topf)
├── all/                   # patches applied to every node
│   ├── 01-general.yaml    #   → symlink to ../shared/patches/general.yaml
│   ├── 02-hostname.yaml.tpl
│   └── 03-network.yaml.tpl
├── control-plane/         # role-specific patches
│   └── 01-cluster.yaml
└── node/<host>/           # node-specific patches (highest precedence)
    └── 01-install.yaml
```

Patches merge in order `all/` → `<role>/` → `node/<host>/`, lexicographically within each folder. Files ending in `.tpl` are Go templates with access to `.Node.Host`, `.Node.Role`, `.Node.Data.<key>`, etc.

The installer image is derived from `talosVersion` + `schematicId` in `topf.yaml`. Schematics are referenced as `schematicId: "@../shared/extensions/<file>.yaml"` and resolved to factory IDs locally — no hardcoded hashes.

**Secrets**: `secretsPath: secrets.sops.yaml` points topf at the encrypted bundle. topf shells out to `sops decrypt`; the age key is wired via `SOPS_AGE_KEY_FILE` (exported by each cluster justfile, pointing at `<repo>/age.key`). Nothing is ever written to disk in plaintext.

---

## Status & Inspection

| Recipe | Description |
|:-------|:------------|
| `status` | `topf nodes` — list nodes with stage, readiness, schematic, Talos version |
| `render` | Write fully merged machine configs to `clusterconfig/<host>.yaml` |
| `diff` | `topf apply --dry-run` — show pending config changes (exit 2 = changes) |
| `schematic-ids` | Print resolved factory schematic IDs for all nodes |

### `just diff`

The primary "what would change?" command. Shows a redacted diff per node without touching anything:

```bash
just diff
```

---

## Deployment

| Recipe | Description |
|:-------|:------------|
| `apply [filter]` | Apply config to all nodes, or a regex subset |
| `apply-controlplanes` | pitower: apply to worker-01/02/03 |
| `apply-workers` | pitower: apply to worker-04/05/06 |
| `bootstrap` | `topf apply --auto-bootstrap` — first-time cluster bring-up |
| `addons` | Build and apply kustomize addons (CNI, kubelet-csr-approver) |

### `just apply [filter]`

Applies configuration with pre-flight health checks, per-node diff + confirmation, and a 30s post-apply stabilization wait. The optional filter is a Go regex on the host name:

```bash
just apply                  # all nodes
just apply 'worker-04'      # one node
just apply 'worker-0[123]'  # control planes
```

### `just bootstrap`

First-time cluster setup: boot the nodes into maintenance mode, then:

```bash
just bootstrap   # topf apply --auto-bootstrap
just kubeconfig
just addons      # install Cilium + kubelet-csr-approver
```

`--auto-bootstrap` has no effect on an already-bootstrapped cluster.

### `just addons`

Builds kustomize addons with Helm support and applies them. Used for CNI (Cilium) and kubelet-csr-approver during bootstrap.

---

## Credentials

| Recipe | Description |
|:-------|:------------|
| `kubeconfig` | Write a short-lived (12h) admin kubeconfig to `clusterconfig/kubeconfig` |
| `talosconfig` | Generate `clusterconfig/talosconfig` from the secrets bundle |
| `merge-config` | Merge the cluster talosconfig into `~/.talos/config` |

The diagnostics recipes below need `clusterconfig/talosconfig` — run `just talosconfig` once first.

---

## Upgrade

| Recipe | Description |
|:-------|:------------|
| `upgrade [filter]` | Upgrade Talos to `talosVersion`/`schematicId` from `topf.yaml` |
| `upgrade-check` | `topf upgrade --dry-run` — show pending upgrades (exit 2 = due) |
| `upgrade-controlplanes` | pitower: upgrade worker-01/02/03 |
| `upgrade-workers` | pitower: upgrade worker-04/05/06 |

topf compares the running version *and* schematic against the target installer image and only upgrades nodes that differ — changing an extension file triggers an upgrade just like a version bump. Upgrades run sequentially with per-node confirmation, preserve data (Talos default since v1.8), and wait for stabilization.

```bash
# 1. bump talosVersion in topf.yaml (and/or edit shared/extensions/*.yaml)
# 2. preview
just upgrade-check
# 3. roll, control planes first
just upgrade-controlplanes
just upgrade-workers
```

!!! info "New schematics"
    Schematic IDs are computed locally. If you create a *brand-new* extension combination the factory has never seen, run any topf command once with `--submit-to-factory` to register it.

---

## Reset & Reboot

| Recipe | Description |
|:-------|:------------|
| `reset <name>` | Reset a node by hostname: wipes STATE+EPHEMERAL, returns to maintenance mode |
| `reboot-controlplanes` | pitower: sequential reboot with wait |
| `reboot-workers` | pitower: sequential reboot with wait |

### `just reset <name>`

```bash
just reset worker-04
```

!!! danger "Destructive Operation"
    Wipes the node's STATE and EPHEMERAL partitions (the machine config is lost; the node comes back in maintenance mode). Re-join with `just apply '<name>'`. Note this differs from the pre-topf recipe, which wiped EPHEMERAL+META but kept STATE.

---

## Diagnostics (talosctl)

| Recipe | Description |
|:-------|:------------|
| `health` | `talosctl health` across all nodes |
| `members` | Show cluster members |
| `uptime` | Uptime for all nodes |
| `services <node>` | List Talos services on a node |
| `image-list <node>` | List container images on a node sorted by size |
| `image-usage` | Image count and containerd disk usage per node |

```bash
just image-usage
```

```text
10.20.10.1      87 images  2.1 GB
10.20.10.2      85 images  2.0 GB
...
```
