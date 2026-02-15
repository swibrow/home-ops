# Prerequisites

Before working with the cluster, ensure you have the required tools installed, the necessary access credentials, and network connectivity to the cluster.

---

## CLI Tools

The following command-line tools are required to manage and interact with the cluster:

| Tool | Purpose | Install |
|:-----|:--------|:--------|
| `talosctl` | Manage Talos Linux nodes (apply configs, upgrade, reboot) | [talos.dev/install](https://www.talos.dev/latest/introduction/getting-started/#talosctl) |
| `kubectl` | Interact with the Kubernetes API | [kubernetes.io/docs](https://kubernetes.io/docs/tasks/tools/) |
| `argocd` | ArgoCD CLI for app management and sync operations | [argo-cd.readthedocs.io](https://argo-cd.readthedocs.io/en/stable/cli_installation/) |
| `sops` | Encrypt and decrypt secrets in the repository | [github.com/getsops/sops](https://github.com/getsops/sops) |
| `age` | Encryption backend used by SOPS for secret management | [github.com/FiloSottile/age](https://github.com/FiloSottile/age) |
| `just` | Task runner for executing justfile recipes | [github.com/casey/just](https://github.com/casey/just) |
| `kustomize` | Build and customize Kubernetes manifests | [kubectl.docs.kubernetes.io](https://kubectl.docs.kubernetes.io/installation/kustomize/) |

!!! tip "Quick install with Homebrew"
    On macOS, all tools can be installed via Homebrew:

    ```bash
    brew install siderolabs/tap/talosctl \
                 kubectl \
                 argocd \
                 sops \
                 age \
                 just \
                 kustomize
    ```

### Optional but Recommended

| Tool | Purpose |
|:-----|:--------|
| `jq` | JSON processing, used in several justfile recipes |
| `yq` | YAML processing for manifest inspection |
| `helm` | Helm chart management (charts are rendered via kustomize, but useful for debugging) |
| `gh` | GitHub CLI for interacting with the repository |
| `tailscale` | VPN client for remote access to internal services |

---

## Access Requirements

### GitHub Repository

You need read access to the [swibrow/home-ops](https://github.com/swibrow/home-ops) repository. Write access is required if you intend to make changes and trigger GitOps deployments.

### Cloudflare API Token

A Cloudflare API token is required for:

- **external-dns** -- automated DNS record management for `example.com`
- **cert-manager** -- DNS-01 challenge solving for TLS certificates
- **cloudflared** -- tunnel authentication for external access

!!! warning "Token scope"
    The token must have `Zone:DNS:Edit` permissions for the `example.com` zone. Store it as an encrypted secret in the repository using SOPS.

### 1Password Connect

The cluster uses [1Password Connect](https://developer.1password.com/docs/connect/) as a secrets backend via [External Secrets Operator](https://external-secrets.io/). You need:

- Access to the 1Password vault that stores cluster secrets
- The 1Password Connect credentials (`1password-credentials.json`) and a connect token

### SOPS / age Key

Secrets in the repository are encrypted with SOPS using an age key. To decrypt or edit secrets, you need the age private key:

```bash
# Export the key so SOPS can find it
export SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt
```

!!! danger "Keep the age key safe"
    The age private key is the master key for all encrypted secrets in the repository. Never commit it to version control.

---

## Network Access

### Local Network

The cluster runs on the `192.168.0.0/24` subnet. You must be on this network (or connected via Tailscale VPN) to reach:

| Endpoint | Address | Purpose |
|:---------|:--------|:--------|
| Talos API | `192.168.0.201` -- `192.168.0.204` | Control plane and worker node management |
| Kubernetes API | `192.168.0.200:6443` | kubectl access (VIP) |
| Envoy External | `192.168.0.239` | External gateway (Cloudflare tunnel target) |
| Envoy Internal | `192.168.0.238` | Internal gateway (LAN / VPN access) |
| ArgoCD | Available via internal gateway | GitOps dashboard |

### Remote Access

For remote access without being on the local network:

- **Tailscale VPN** -- connects you to the internal network and the `envoy-internal` gateway
- **Cloudflare Tunnel** -- exposes selected services via `*.example.com` through the external gateway

---

## Verify Your Setup

Once all tools are installed and credentials are in place, verify connectivity:

```bash
# Check Talos API connectivity
talosctl version --nodes 192.168.0.201

# Check Kubernetes API connectivity
kubectl cluster-info

# Verify SOPS can decrypt secrets
sops -d pitower/talos/secrets.sops.yaml > /dev/null && echo "SOPS decryption OK"

# Check ArgoCD connectivity
argocd app list
```

!!! success "Ready to go"
    If all four commands succeed, you are ready to work with the cluster. Head to the [Architecture Overview](architecture-overview.md) to understand how everything fits together.
