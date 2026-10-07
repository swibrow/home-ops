# Prerequisites

Before working with the cluster, ensure you have the required tools installed, the necessary access credentials, and network connectivity to the cluster.

---

## CLI Tools

Most tools are pinned in the root `mise.toml`; running `mise install` from the repository root installs them at the right versions.

| Tool | Purpose | Source |
|:-----|:--------|:-------|
| `talosctl` | Read-only Talos diagnostics (health, services, logs) | `mise.toml` |
| `kubectl` | Interact with the Kubernetes API | `mise.toml` |
| `kustomize` | Render manifests and the Talos bootstrap addons | `mise.toml` |
| `helm` | Chart rendering (kustomize `helmCharts` uses it) | `mise.toml` |
| `sops` | Encrypt and decrypt secrets; topf shells out to it | `mise.toml` |
| `jq` | JSON processing, used in several recipes | `mise.toml` |
| `topf` | Talos lifecycle: render, apply, upgrade, reset | [postfinance/topf](https://github.com/postfinance/topf) (not in `mise.toml`) |
| `just` | Task runner for the justfile recipes | [casey/just](https://github.com/casey/just) |

### Optional but Recommended

| Tool | Purpose |
|:-----|:--------|
| `argocd` | ArgoCD CLI for app inspection and sync operations |
| `infisical` | Infisical CLI, wrapped by `just infisical ls` / `just infisical set` |
| `terraform` | Plans and applies under `terraform/` |
| `yq` | YAML processing for manifest inspection |
| `gh` | GitHub CLI for interacting with the repository |
| `tailscale` | VPN client for remote access to internal services |

---

## Access Requirements

### GitHub Repository

You need read access to the [swibrow/home-ops](https://github.com/swibrow/home-ops) repository. Write access is required if you intend to make changes and trigger GitOps deployments.

### Infisical

App secrets live in [Infisical](https://infisical.com/) (EU instance, project ID set in `mise.toml`) at `/category/app/SECRET_NAME`, and are synced into the cluster by [External Secrets Operator](https://external-secrets.io/) through the `infisical` ClusterSecretStore. You need access to the Infisical project to read or set them.

### SOPS / age Key

Talos secrets (`talos/pitower/secrets.sops.yaml`) and the ArgoCD bootstrap secrets (`kubernetes/bootstrap/*.sops.yaml`) are encrypted with SOPS using a single age key (`.sops.yaml`). `mise.toml` points `SOPS_AGE_KEY_FILE` at the key:

```bash
export SOPS_AGE_KEY_FILE=~/.config/mise/age.txt
```

> [!CAUTION]
> **Keep the age key safe**
>
> The age private key decrypts every encrypted secret in the repository, including the Talos cluster CA. Never commit it to version control.

### Cloudflare API Token

A Cloudflare API token (stored in Infisical) is used by:

- **external-dns**: DNS records for `wibrow.dev`
- **cert-manager**: DNS-01 challenges for Let's Encrypt certificates

---

## Network Access

Cluster nodes live on VLAN 20 (`servers`, `10.20.0.0/16`). You must be on the home network (or connected via Tailscale) to reach:

| Endpoint | Address | Purpose |
|:---------|:--------|:--------|
| Talos API | `10.20.10.1` - `10.20.10.11` | Node management (port 50000) |
| Kubernetes API | `10.20.10.0:6443` | kubectl access (control plane VIP) |
| Envoy External | `10.20.10.239` | Public gateway (towonel tunnel target) |
| Envoy Internal | `10.20.10.238` | Internal gateway (LAN / VPN access) |
| ArgoCD | `argocd.wibrow.dev` | GitOps dashboard |

> [!WARNING]
> **KUBECONFIG**
>
> `mise.toml` sets `KUBECONFIG=~/.kube/pitower.yaml`. The default `~/.kube/config` may point at a different cluster, so always work from inside the repository (or export the variable yourself).

### Remote Access

- **Tailscale**: the `pitower` Connector advertises the home subnets (including VLAN 20 and the pod CIDR), so internal services and the APIs above are reachable remotely
- **towonel tunnel**: public apps on `*.wibrow.dev` reach `envoy-external` through the hub on a VPS

---

## Verify Your Setup

Once all tools are installed and credentials are in place, verify connectivity:

```bash
# Generate a talosconfig and check the Talos API
just talos pitower talosconfig
just talos pitower members

# Check Kubernetes API connectivity
kubectl get nodes

# Verify SOPS can decrypt the Talos secrets
sops -d talos/pitower/secrets.sops.yaml > /dev/null && echo "SOPS decryption OK"

# Check topf can read the cluster definition (runs `topf nodes`, read-only)
just talos pitower status
```

> [!TIP]
> **Ready to go**
>
> If all commands succeed, you are ready to work with the cluster. Head to the [Architecture Overview](architecture-overview.md) to understand how everything fits together.
