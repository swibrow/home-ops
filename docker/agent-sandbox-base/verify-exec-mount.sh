#!/bin/sh
# Fails loudly if the NFS bin-cache mount is noexec — binaries can't run from a noexec
# mount, and this is meant to catch a misconfigured pod spec (e.g. a stray mountOption)
# before anything downstream tries and fails to exec a cached binary. NFS mounts are
# exec by default; this only ever trips if something explicitly changed that.
set -eu

mountpoint="${1:-${MISE_DATA_DIR_MOUNT:-/mnt/nfs}}"

line="$(mount | grep -F " on $mountpoint " || true)"

if [ -z "$line" ]; then
    echo "verify-exec-mount: $mountpoint is not a mount point" >&2
    exit 1
fi

case "$line" in
    *noexec*)
        echo "verify-exec-mount: $mountpoint is mounted noexec, binaries in the bin-cache cannot run: $line" >&2
        exit 1
        ;;
esac

echo "verify-exec-mount: $mountpoint is exec-capable"
