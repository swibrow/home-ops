#!/bin/sh
# hermes caches skills.external_dirs resolved through the `current` symlink,
# keyed on config.yaml's mtime; bumping it makes hermes follow the new worktree.
touch /opt/data/config.yaml
