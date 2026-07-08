#!/bin/sh
# Server-aware kubectl wrapper for the NFS bin-cache (kubernetes/apps/pitower/ai/bin-cache/).
#
# kubectl must stay within +/-1 minor of the API server it's talking to, and this fleet
# runs mixed k8s minors across clusters, so a single pinned kubectl in the sandbox image
# doesn't work. This wrapper resolves the active kube-context's server minor and execs the
# matching binary from the cache, caching the resolution per-context (tmpfs) so it costs one
# API round-trip per context, not per invocation.
#
# Installed at /usr/local/bin/kubectl, ahead of the mise-managed tools on PATH — there is no
# separate generic "kubectl" shim, this wrapper is the only kubectl entry point.
set -eu

data_dir="${MISE_DATA_DIR:-/mnt/nfs/bin-cache}/installs/kubectl"
cache_dir="${MISE_CACHE_DIR:-/tmp/mise/cache}/kubectl-context"

if [ ! -d "$data_dir" ]; then
    echo "kubectl-wrapper: no kubectl versions found under $data_dir" >&2
    exit 1
fi

# Highest installed version — used both as the bootstrap binary (to query the server) and
# as the fallback if the server can't be reached or no matching minor is cached.
latest_installed() {
    find "$data_dir" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null \
        | sort -V | tail -1
}

bootstrap_version="$(latest_installed)"
if [ -z "$bootstrap_version" ]; then
    echo "kubectl-wrapper: no kubectl versions installed under $data_dir" >&2
    exit 1
fi
bootstrap_kubectl="$data_dir/$bootstrap_version/bin/kubectl"

resolve_version() {
    context="$1"
    mkdir -p "$cache_dir" 2>/dev/null || true
    cache_file="$cache_dir/$context"

    if [ -n "$context" ] && [ -s "$cache_file" ]; then
        cat "$cache_file"
        return 0
    fi

    server_minor="$("$bootstrap_kubectl" get --raw /version 2>/dev/null \
        | jq -r '.minor // empty' 2>/dev/null | tr -d -c '0-9')"

    if [ -z "$server_minor" ]; then
        # Server unreachable — fall back to the newest installed version.
        echo "$bootstrap_version"
        return 0
    fi

    target_minor="1.${server_minor}"
    resolved="$(find "$data_dir" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null \
        | grep "^${target_minor}\." | sort -V | tail -1)"

    if [ -z "$resolved" ]; then
        # No exact minor match cached — fall back to the newest installed version.
        resolved="$bootstrap_version"
    fi

    if [ -n "$context" ]; then
        printf '%s' "$resolved" > "$cache_file" 2>/dev/null || true
    fi
    echo "$resolved"
}

current_context="$("$bootstrap_kubectl" config current-context 2>/dev/null || true)"
resolved_version="$(resolve_version "$current_context")"

exec "$data_dir/$resolved_version/bin/kubectl" "$@"
