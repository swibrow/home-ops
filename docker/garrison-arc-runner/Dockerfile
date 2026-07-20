# Self-hosted GitHub Actions runner for the swibrow/garrison repo's `garrison`
# scale set. Stock actions-runner plus what garrison's CI gates need that the
# stripped-down base image lacks:
#   - tmux       gate 4 drives a real tmux session
#   - unzip      oven-sh/setup-bun extracts bun with it
#   - libatomic1 the Node 26 that actions/setup-node installs links libatomic.so.1
# LANG=C.UTF-8: the base image leaves the locale unset, so tmux mangles the
# non-ASCII pane titles (✳ / braille spinner) garrison's status discovery keys
# on — a UTF-8 locale keeps them intact.
# The first ARG *_VERSION drives the published image tag (see build-docker-images.yaml).
# IMAGE_VERSION is <runner-version>-<revision>: bump the revision whenever this
# image's contents change without the base runner version moving, so the scale
# set pulls a fresh tag instead of a cached one (default pull policy is IfNotPresent).
ARG IMAGE_VERSION=2.335.1-2
ARG RUNNER_VERSION=2.336.0

FROM ghcr.io/actions/actions-runner:${RUNNER_VERSION}

USER root
RUN apt-get update \
    && apt-get install -y --no-install-recommends tmux unzip libatomic1 \
    && rm -rf /var/lib/apt/lists/*
ENV LANG=C.UTF-8
USER runner
