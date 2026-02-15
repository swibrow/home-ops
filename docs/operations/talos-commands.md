# Talos Commands

Common `talosctl` commands for managing and debugging the Talos Linux cluster. These commands complement the [justfile recipes](justfile-recipes.md) for lower-level operations.

!!! tip "Default Endpoint"
    Most commands default to the endpoint configured in `~/.talos/config`. Set the default node/endpoint with:
    ```bash
    talosctl config endpoint 192.168.0.201
    talosctl config node 192.168.0.201
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
talosctl health --nodes 192.168.0.201
```

### Node Dashboard

Open an interactive dashboard showing real-time CPU, memory, and service status for a node.

```bash
talosctl dashboard
```

```bash
talosctl dashboard --nodes 192.168.0.204
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
talosctl services --nodes 192.168.0.201
```

### Service Logs

View logs for a specific Talos service (e.g., `etcd`, `kubelet`, `apid`, `containerd`).

```bash
# etcd logs
talosctl logs etcd --nodes 192.168.0.201

# kubelet logs
talosctl logs kubelet --nodes 192.168.0.201

# Follow logs in real time
talosctl logs etcd --nodes 192.168.0.201 -f
```

### Service Status

Get detailed status for a specific service.

```bash
talosctl service etcd --nodes 192.168.0.201
```

---

## etcd Operations

### Membership

List etcd cluster members and their status.

```bash
talosctl etcd members --nodes 192.168.0.201
```

### Etcd Status

Check etcd health and leadership.

```bash
talosctl etcd status --nodes 192.168.0.201
```

### Remove a Member

Remove a failed etcd member (use with caution).

```bash
talosctl etcd remove-member <member-id> --nodes 192.168.0.201
```

### Etcd Snapshot

Take a snapshot of the etcd database.

```bash
talosctl etcd snapshot etcd-backup.snapshot --nodes 192.168.0.201
```

!!! warning "etcd Quorum"
    With a 3-node control plane, losing more than 1 etcd member will break quorum. Always verify etcd membership before performing maintenance.

---

## Kubeconfig

### Refresh Kubeconfig

Generate or refresh the kubeconfig file for kubectl access.

```bash
talosctl kubeconfig --nodes 192.168.0.200
```

Write to a specific path:

```bash
talosctl kubeconfig ~/.kube/config --nodes 192.168.0.200
```

!!! note "VIP Address"
    Use the VIP address (192.168.0.200) for kubeconfig generation to ensure HA access to the API server.

---

## Configuration Inspection

### View Running Config

Inspect the current machine configuration running on a node.

```bash
talosctl get machineconfig --nodes 192.168.0.201 -o yaml
```

### Compare Configs

Diff the running config against a file.

```bash
talosctl apply-config --nodes 192.168.0.201 --file ./clusterconfig/worker-01.yaml --dry-run
```

### Version Information

Check the Talos version on a node.

```bash
talosctl version --nodes 192.168.0.201
```

---

## Resource Inspection

### Kernel Logs (dmesg)

View kernel messages from a node.

```bash
talosctl dmesg --nodes 192.168.0.204
```

Follow kernel messages:

```bash
talosctl dmesg --nodes 192.168.0.204 -f
```

### Process List

List running processes on a node.

```bash
talosctl processes --nodes 192.168.0.201
```

### Disk Usage

Check disk usage on a node.

```bash
talosctl usage /var --nodes 192.168.0.201
```

### Container Images

List all container images on a node.

```bash
talosctl image list --nodes 192.168.0.201
```

### Network Interfaces

Show network interfaces and addresses.

```bash
talosctl get addresses --nodes 192.168.0.201
```

### Routes

Show routing table.

```bash
talosctl get routes --nodes 192.168.0.201
```

---

## Node Operations

### Reboot

Reboot a node (with wait for it to come back).

```bash
talosctl reboot --nodes 192.168.0.204 --wait
```

### Shutdown

Shut down a node.

```bash
talosctl shutdown --nodes 192.168.0.204
```

### Reset

Reset a node, wiping its state.

```bash
talosctl reset \
    --system-labels-to-wipe=EPHEMERAL \
    --system-labels-to-wipe=META \
    --reboot \
    --graceful=false \
    --nodes 192.168.0.204
```

### Upgrade

Upgrade Talos on a node to a new version.

```bash
talosctl upgrade \
    --image factory.talos.dev/installer/<schematic-id>:v1.12.4 \
    --nodes 192.168.0.201 \
    --preserve \
    --wait
```

---

## Troubleshooting Commands

### Check Pod CIDR and Service CIDR

```bash
talosctl get clusterconfig --nodes 192.168.0.201 -o yaml | grep -A5 clusterNetwork
```

### Check Certificate Validity

```bash
talosctl get certificate --nodes 192.168.0.201
```

### Read Machine Config Patches

```bash
talosctl get machineconfig --nodes 192.168.0.201 -o yaml
```

### Check Time Sync

```bash
talosctl get timestatus --nodes 192.168.0.201
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
