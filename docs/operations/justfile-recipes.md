# Justfile Recipes

Reference for the repo's [just](https://github.com/casey/just) recipes. The root `justfile` loads one module per area: most live in `.justfiles/<module>/justfile`, Talos in `talos/` and Ansible in `ansible/`.

> [!TIP]
> **Running Recipes**
>
> ```bash
> just --list                          # root recipes and modules
> just talos pitower <recipe>          # or  just talos::pitower::<recipe>
> just k8s es-sync <namespace> <name>
> ```

---

## Modules

| Module | Source | Recipes |
|:-------|:-------|:--------|
| `talos` | `talos/justfile` → `talos/pitower/justfile` + `talos/talos.justfile` | Talos lifecycle (topf) and diagnostics, see below |
| `ansible` | `ansible/justfile` | `deploy`, `check`, `deploy-ovh-vps`, `deploy-nut`, `deploy-homeassistant`, ... (see `ansible/README.md`) |
| `k8s` | `.justfiles/k8s` | `delete-failed-pods`, `delete-succeeded-pods`, `delete-pending-pods`, `clear-restarts`, `clear-restarts-sequential`, `es-sync` |
| `vm` | `.justfiles/vm` | `status`, `start`, `stop`, `restart` for KubeVirt VMs in `vms` (default `omarchy`) |
| `infisical` | `.justfiles/infisical` | `ls <path>`, `set <path> <name>` (value from stdin or prompt) |
| `kanidm` | `.justfiles/kanidm` | `ls`, `oidc-client`, `oidc-secret` (copies a client secret into Infisical) |
| `tf` | `.justfiles/terraform` | `init-unifi`, `plan-unifi`, `apply-unifi` (and older generic recipes) |
| `docs` | `.justfiles/docs` | `sync` (`bun install`), `serve` (port 8888), `build` (Astro build, Pagefind index, link check) |
| `sops` | `.justfiles/sops` | `re-encrypt` every `*.sops.yaml` |
| `gh` | `.justfiles/gh` | `repo`, `update-environment-variables` |

Root-level recipes: `pre-commit-init`, `pre-commit-check`, `secret-ls`, `secret-encrypt`, `gh-all`.

> [!NOTE]
> **Cluster context**
>
> The `k8s` recipes take a kube context name (`cluster`), several defaulting to the current context. `KUBECONFIG` from `mise.toml` is `~/.kube/pitower.yaml`; the default `~/.kube/config` is a different cluster.

---

## Talos

Lifecycle recipes are defined in `talos/talos.justfile` and wrap [topf](https://github.com/postfinance/topf); diagnostics wrap `talosctl`. `talos/pitower/justfile` imports it and adds the node-group recipes. Run them from `talos/pitower` (`just <recipe>`) or from the repo root (`just talos pitower <recipe>`).

> [!WARNING]
> **No confirmation prompt**
>
> `talos.justfile` exports `TOPF_CONFIRM=false`, so the recipes apply and upgrade **without** topf's per-node y/n prompt. Preview with `just diff` / `just upgrade-check` first, or run `mise exec -- topf ...` directly to keep the prompt.

### How It Works

topf reads `topf.yaml` in the cluster directory and assembles each node's machine config from layered strategic-merge patches:

```text
talos/pitower/
├── topf.yaml              # cluster identity, nodes, versions, schematics
├── secrets.sops.yaml      # SOPS-encrypted secrets bundle (decrypted by topf)
├── extensions/            # factory schematics: amd, intel, r630, rpi-poe, nvidia
├── all/                   # patches applied to every node
│   ├── 01-general.yaml
│   ├── 02-hostname.yaml.tpl
│   └── 03-network.yaml.tpl
├── control-plane/         # role-specific patches
│   ├── 01-cluster.yaml
│   └── 02-uinput.yaml
└── node/<host>/           # node-specific patches (highest precedence)
    └── 01-install.yaml
```

Patches merge in order `all/` → `<role>/` → `node/<host>/`, lexicographically within each folder. Files ending in `.tpl` are Go templates with access to `.Node.Host`, `.Node.Role`, `.Node.Data.<key>`, etc.

The installer image is derived from `talosVersion` + `schematicId` in `topf.yaml`. Schematics are referenced as `schematicId: "@extensions/<file>.yaml"` and resolved to factory IDs locally.

**Secrets**: `secretsPath: secrets.sops.yaml` points topf at the encrypted bundle, which it decrypts via sops. The age key comes from `SOPS_AGE_KEY_FILE`: `mise.toml` sets it to `~/.config/mise/age.txt`; the cluster justfile only falls back to `<repo>/age.key` when it is unset.

### Status & Inspection

| Recipe | Description |
|:-------|:------------|
| `status` | `topf nodes`: nodes with stage, readiness, schematic, Talos version |
| `render` | Write fully merged machine configs to `output/` |
| `diff` | `topf apply --dry-run`: pending config changes (exit 2 = changes, treated as success) |
| `schematic-ids` | Print resolved factory schematic IDs for all nodes |

### Deployment

| Recipe | Description |
|:-------|:------------|
| `apply [filter]` | Apply config to all nodes, or a regex subset of host names |
| `apply-controlplanes` | Apply to the control planes (worker-01/02/03) |
| `apply-workers` | Apply to worker-04..10 and worker-ai-01 |
| `bootstrap` | `topf apply --auto-bootstrap`: first-time cluster bring-up |
| `addons` | Build and apply the kustomize addons (Cilium, kubelet-csr-approver) |
| `render-addons` | Re-render `addons-rendered.yaml`, which Talos applies at bootstrap via `cluster.extraManifests` |

```bash
just apply                  # all nodes
just apply 'worker-04'      # one node
just apply 'worker-0[123]'  # control planes (apply-controlplanes only previews)
```

`--auto-bootstrap` has no effect on an already-bootstrapped cluster. For a brand-new cluster: `just bootstrap`, `just kubeconfig`, `just addons`.

### Credentials

| Recipe | Description |
|:-------|:------------|
| `kubeconfig` | Write a short-lived (12h) admin kubeconfig to `output/kubeconfig` |
| `talosconfig` | Generate `output/talosconfig` from the secrets bundle |
| `merge-config` | Merge the cluster talosconfig into `~/.talos/config` |

The diagnostics recipes need `output/talosconfig`; run `just talosconfig` once first.

### Upgrade

| Recipe | Description |
|:-------|:------------|
| `upgrade [filter]` | Upgrade Talos to `talosVersion`/`schematicId` from `topf.yaml` |
| `upgrade-check` | `topf upgrade --dry-run`: pending upgrades (exit 2 = due) |
| `upgrade-controlplanes` | Upgrade worker-01/02/03 |
| `upgrade-workers` | Upgrade worker-04..10 and worker-ai-01 |

topf compares the running version *and* schematic against the target installer image and only upgrades nodes that differ, so changing an extension file triggers an upgrade just like a version bump. By default it drains each node, upgrades one node at a time, and waits for it to stay Ready (`--stabilization-duration`, 30s). See [Upgrades](upgrades.md).

> [!NOTE]
> **New schematics**
>
> topf computes schematic IDs locally. A *brand-new* extension combination must be registered with the Image Factory before an install, or the installer image 404s: run topf once with the global `--submit-to-factory`, or `curl -X POST --data-binary @extensions/<file>.yaml https://factory.talos.dev/schematics`.

### Reset & Reboot

| Recipe | Description |
|:-------|:------------|
| `reset <name>` | Reset a node by hostname: wipes STATE+EPHEMERAL, returns to maintenance mode |
| `reboot-controlplanes` | Sequential `talosctl reboot --wait` of 10.20.10.1-3 |
| `reboot-workers` | Sequential `talosctl reboot --wait` of 10.20.10.4-11 |

> [!CAUTION]
> **Destructive Operation**
>
> `reset` wipes the node's STATE and EPHEMERAL partitions (the machine config is lost; the node comes back in maintenance mode). Re-join with `just apply '<name>'`.

### Diagnostics (talosctl)

| Recipe | Description |
|:-------|:------------|
| `health` | `talosctl health` across all nodes |
| `members` | Show cluster members |
| `uptime` | Uptime for all nodes |
| `services <node>` | List Talos services on a node |
| `image-list <node>` | List container images on a node sorted by size |
| `image-usage` | Image count and containerd disk usage per node |
