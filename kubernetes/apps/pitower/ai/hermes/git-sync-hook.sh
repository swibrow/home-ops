#!/bin/sh
set -eu
# hermes caches skills.external_dirs resolved through the `current` symlink,
# keyed on config.yaml's mtime; bumping it makes hermes follow the new worktree.
touch /opt/data/config.yaml
# hermes cron only runs scripts that resolve inside $HERMES_HOME/scripts, so
# synced scripts are copied there rather than linked.
mkdir -p /opt/data/scripts
cp -f scripts/* /opt/data/scripts/
