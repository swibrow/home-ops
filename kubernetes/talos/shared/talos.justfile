# Shared Talos recipes — imported by each cluster justfile.
# Requires the importing justfile to define:
#   - nodes: space-separated node IPs
#   - talosconfig: path to the cluster's talosconfig

_endpoint := replace(nodes, " ", ",")
_talos := "TALOSCONFIG=" + talosconfig + " talosctl --endpoints " + _endpoint

# Apply config to a node by name
[working-directory: 'clusterconfig']
apply-node name:
    #!/usr/bin/env bash
    set -euo pipefail
    ip=$({{ _talos }} -n {{ _endpoint }} get members -o json | jq -rs --arg h "{{ name }}" '[.[] | select(.spec.hostname == $h) | .spec.addresses[0]][0]')
    echo "Applying config to {{ name }} (${ip})"
    {{ _talos }} apply-config --nodes "${ip}" --file ./{{ name }}.yaml

# Build and apply kustomize addons (CNI + kubelet-csr-approver)
addons:
    kustomize build ./addons --enable-helm | kubectl apply -f -

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
