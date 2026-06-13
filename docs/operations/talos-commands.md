# Talos Commands

Common `talosctl` commands for debugging the Talos Linux cluster. Cluster lifecycle (config generation, apply, upgrade, reset) is handled by [topf via the justfile recipes](justfile-recipes.md) — `talosctl` complements it for read-only inspection and low-level operations.

!!! tip "Default Endpoint"
    Most commands default to the endpoint configured in `~/.talos/config`. Set the default node/endpoint with:
    ```bash
    talosctl config endpoint 10.20.10.1
    talosctl config node 10.20.10.1
    ```

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

!!! warning "etcd Quorum"
    With a 3-node control plane, losing more than 1 etcd member will break quorum. Always verify etcd membership before performing maintenance.

---

## Kubeconfig

### Refresh Kubeconfig

Generate or refresh the kubeconfig file for kubectl access.

```bash
talosctl kubeconfig --nodes 10.20.10.0
```

Write to a specific path:

```bash
talosctl kubeconfig ~/.kube/config --nodes 10.20.10.0
```

!!! note "VIP Address"
    Use the VIP address (10.20.10.0) for kubeconfig generation to ensure HA access to the API server.

---

## Configuration Inspection

### View Running Config

Inspect the current machine configuration running on a node.

```bash
talosctl get machineconfig --nodes 10.20.10.1 -o yaml
```

### Compare Configs

Diff the running config against the declared state (all nodes, redacted):

```bash
just diff   # topf apply --dry-run
```

Or against a single rendered file (`just render` writes them to `output/`):

```bash
talosctl apply-config --nodes 10.20.10.1 --file ./output/worker-01.yaml --dry-run
```

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

### Reset

Reset a node, wiping its state.

```bash
talosctl reset \
    --system-labels-to-wipe=EPHEMERAL \
    --system-labels-to-wipe=META \
    --reboot \
    --graceful=false \
    --nodes 10.20.10.4
```

### Upgrade

Upgrade Talos on a node to a new version.

```bash
talosctl upgrade \
    --image factory.talos.dev/installer/<schematic-id>:v1.12.4 \
    --nodes 10.20.10.1 \
    --preserve \
    --wait
```

---

## Troubleshooting Commands

### Check Pod CIDR and Service CIDR

```bash
talosctl get clusterconfig --nodes 10.20.10.1 -o yaml | grep -A5 clusterNetwork
```

### Check Certificate Validity

```bash
talosctl get certificate --nodes 10.20.10.1
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
