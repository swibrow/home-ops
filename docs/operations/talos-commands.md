# Talos Commands

Common `talosctl` commands for debugging the Talos Linux cluster. Cluster lifecycle (apply, upgrade, reset) is handled by [topf](justfile-recipes.md#talos) (`mise exec -- topf ...` from `talos/pitower`); `talosctl` complements it for read-only inspection and low-level operations.

> [!TIP]
> **Talosconfig**
>
> Generate the talosconfig from the secrets bundle and merge it into `~/.talos/config`:
> ```bash
> cd talos/pitower
> just talosconfig && just merge-config
> talosctl config endpoint 10.20.10.1 10.20.10.2 10.20.10.3
> talosctl config node 10.20.10.1
> ```

---

## Health Checks

### Cluster Health

Check the overall health of the cluster, including etcd, kubelet, and API server status.

```bash
talosctl health
```

Target a specific node:

```bash
talosctl health --nodes 10.20.10.1
```

### Node Dashboard

Open an interactive dashboard showing real-time CPU, memory, and service status for a node.

```bash
talosctl dashboard
```

```bash
talosctl dashboard --nodes 10.20.10.4
```

### Member List

List all cluster members as seen by Talos.

```bash
talosctl get members
```

JSON output (useful for scripting):

```bash
talosctl get members -o json | jq '.spec'
```

---

## Service Management

### List Services

Show the status of all Talos services on a node.

```bash
talosctl services --nodes 10.20.10.1
```

### Service Logs

View logs for a specific Talos service (e.g., `etcd`, `kubelet`, `apid`, `containerd`).

```bash
# etcd logs
talosctl logs etcd --nodes 10.20.10.1

# kubelet logs
talosctl logs kubelet --nodes 10.20.10.1

# Follow logs in real time
talosctl logs etcd --nodes 10.20.10.1 -f
```

### Service Status

Get detailed status for a specific service.

```bash
talosctl service etcd --nodes 10.20.10.1
```

---

## etcd Operations

### Membership

List etcd cluster members and their status.

```bash
talosctl etcd members --nodes 10.20.10.1
```

### Etcd Status

Check etcd health and leadership.

```bash
talosctl etcd status --nodes 10.20.10.1
```

### Remove a Member

Remove a failed etcd member (use with caution).

```bash
talosctl etcd remove-member <member-id> --nodes 10.20.10.1
```

### Etcd Snapshot

Take a snapshot of the etcd database.

```bash
talosctl etcd snapshot etcd-backup.snapshot --nodes 10.20.10.1
```

> [!WARNING]
> **etcd Quorum**
>
> With a 3-node control plane, losing more than 1 etcd member will break quorum. Always verify etcd membership before performing maintenance.

---

## Kubeconfig

### Refresh Kubeconfig

Generate a kubeconfig for kubectl access. `mise.toml` points `KUBECONFIG` at `~/.kube/pitower.yaml`; do not write to `~/.kube/config`, which is a different cluster.

```bash
talosctl kubeconfig ~/.kube/pitower.yaml --nodes 10.20.10.1
```

`just kubeconfig` (topf) writes a short-lived (12h) admin kubeconfig to `output/kubeconfig` instead.

> [!NOTE]
> **VIP Address**
>
> The kubeconfig's server is the API VIP `https://10.20.10.0:6443`. Talos API calls go to a node IP, since the VIP is not a Talos API endpoint.

---

## Configuration Inspection

### View Running Config

Inspect the current machine configuration running on a node.

```bash
talosctl get machineconfig --nodes 10.20.10.1 -o yaml
```

### Compare Configs

Diff the running config against the declared state (redacted; exit 2 = changes pending):

```bash
mise exec -- topf apply --dry-run                              # all nodes
mise exec -- topf apply --dry-run --nodes-filter '^worker-01$'  # one node
```

`topf render` writes the full machine configs to `output/` (gitignored) for inspection.

### Version Information

Check the Talos version on a node.

```bash
talosctl version --nodes 10.20.10.1
```

---

## Resource Inspection

### Kernel Logs (dmesg)

View kernel messages from a node.

```bash
talosctl dmesg --nodes 10.20.10.4
```

Follow kernel messages:

```bash
talosctl dmesg --nodes 10.20.10.4 -f
```

### Process List

List running processes on a node.

```bash
talosctl processes --nodes 10.20.10.1
```

### Disk Usage

Check disk usage on a node.

```bash
talosctl usage /var --nodes 10.20.10.1
```

### Container Images

List all container images on a node.

```bash
talosctl image list --nodes 10.20.10.1
```

### Network Interfaces

Show network interfaces and addresses.

```bash
talosctl get addresses --nodes 10.20.10.1
```

### Routes

Show routing table.

```bash
talosctl get routes --nodes 10.20.10.1
```

---

## Node Operations

### Reboot

Reboot a node (with wait for it to come back).

```bash
talosctl reboot --nodes 10.20.10.4 --wait
```

### Shutdown

Shut down a node.

```bash
talosctl shutdown --nodes 10.20.10.4
```

### Reset and Upgrade

Use topf for both, so the node ends up matching `topf.yaml`:

```bash
cd talos/pitower
mise exec -- topf reset --nodes-filter '^worker-04$' --full=false   # or: just reset worker-04
mise exec -- topf upgrade --nodes-filter '^worker-04$'
```

See [Upgrades](upgrades.md).

---

## Troubleshooting Commands

### Check Pod CIDR and Service CIDR

```bash
talosctl get machineconfig --nodes 10.20.10.1 -o yaml | grep -A3 -E 'podSubnets|serviceSubnets'
kubectl get nodes -o custom-columns=NAME:.metadata.name,PODCIDRS:.spec.podCIDRs
```

### Check Certificate SANs

```bash
talosctl get certsan --nodes 10.20.10.1 -o yaml
```

### Read Machine Config Patches

```bash
talosctl get machineconfig --nodes 10.20.10.1 -o yaml
```

### Check Time Sync

```bash
talosctl get timestatus --nodes 10.20.10.1
```

---

## Useful Aliases

Consider adding these aliases to your shell configuration:

```bash
alias tc='talosctl'
alias tcd='talosctl dashboard'
alias tch='talosctl health'
alias tcl='talosctl logs'
alias tcs='talosctl services'
alias tcm='talosctl get members'
```
