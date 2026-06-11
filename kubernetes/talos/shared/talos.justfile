# Shared Talos recipes — imported by each cluster justfile.
#
# Cluster lifecycle is managed by topf (https://github.com/postfinance/topf):
# it reads ./topf.yaml, decrypts secrets.sops.yaml transparently via sops
# (age key from SOPS_AGE_KEY_FILE, exported by the cluster justfile) and
# layers patches from all/, control-plane/, worker/ and node/<host>/.
#
# talosctl remains for read-only diagnostics that topf does not cover.
#
# Requires the importing justfile to define:
#   - nodes: space-separated node IPs (diagnostics only)
#   - talosconfig: path to the cluster's talosconfig

_endpoint := replace(nodes, " ", ",")
_talos := "TALOSCONFIG=" + talosconfig + " talosctl --endpoints " + _endpoint

# --- lifecycle (topf) ---

# Show all nodes and their current state
status:
    topf nodes

# Render full machine configs to clusterconfig/ for inspection
render:
    topf render --output ./clusterconfig

# Show pending config changes without applying (exit 2 = changes pending)
diff:
    topf apply --dry-run

# Apply config to all nodes, or a regex subset (e.g. just apply 'worker-0[12]')
apply filter='.*':
    topf apply --nodes-filter '{{ filter }}'

# Bootstrap a brand-new cluster (nodes booted into maintenance mode)
bootstrap:
    topf apply --auto-bootstrap

# Upgrade Talos to the talosVersion/schematicId in topf.yaml (preserves data)
upgrade filter='.*':
    topf upgrade --nodes-filter '{{ filter }}'

# Preview pending upgrades (exit 2 = upgrades due)
upgrade-check:
    topf upgrade --dry-run

# Reset a node by name: wipes STATE+EPHEMERAL, node returns to maintenance mode
reset name:
    topf reset --nodes-filter '^{{ name }}$' --full=false

# Write a short-lived (12h) admin kubeconfig to clusterconfig/kubeconfig
kubeconfig:
    @mkdir -p ./clusterconfig
    topf kubeconfig > ./clusterconfig/kubeconfig
    @echo "export KUBECONFIG=$PWD/clusterconfig/kubeconfig"

# Generate the talosconfig used by the diagnostics recipes below
talosconfig:
    @mkdir -p ./clusterconfig
    topf talosconfig > {{ talosconfig }}

# Print resolved factory schematic IDs for all nodes
schematic-ids:
    topf schematic-ids

# --- addons ---

# Build and apply kustomize addons (CNI + kubelet-csr-approver)
addons:
    kustomize build ./addons --enable-helm | kubectl apply -f -

# --- diagnostics (talosctl, read-only) ---

# List container images on a node sorted by size
image-list node:
    {{ _talos }} -n {{ node }} image list | sort -k4 -h

# Show image count and disk usage per node
image-usage:
    #!/usr/bin/env bash
    set -euo pipefail
    for node in {{ nodes }}; do
        count=$({{ _talos }} -n "$node" image list 2>/dev/null | tail -n +2 | wc -l)
        size=$({{ _talos }} -n "$node" usage /var/lib/containerd --depth 0 2>/dev/null | tail -1 | awk '{printf "%.1f", $2/1024/1024/1024}')
        printf "%-16s %4d images  %s GB\n" "$node" "$count" "$size"
    done

# Show uptime for all nodes
uptime:
    #!/usr/bin/env bash
    set -euo pipefail
    for node in {{ nodes }}; do
        raw=$({{ _talos }} -n "$node" read /proc/uptime 2>/dev/null | awk '{print $1}')
        days=$((${raw%.*} / 86400))
        hours=$(( (${raw%.*} % 86400) / 3600 ))
        mins=$(( (${raw%.*} % 3600) / 60 ))
        printf "%-16s %dd %dh %dm\n" "$node" "$days" "$hours" "$mins"
    done

# Show node members
members:
    @{{ _talos }} -n {{ _endpoint }} get members -o table

# Run talosctl health check
health:
    {{ _talos }} -n {{ _endpoint }} health

# List services on a node
services node:
    {{ _talos }} -n {{ node }} services

# Merge cluster talosconfig into ~/.talos/config
merge-config:
    talosctl config merge {{ talosconfig }}
