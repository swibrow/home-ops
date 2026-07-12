# Self-hosted GitHub Actions runner for the swibrow/garrison repo's `garrison`
# scale set. Stock actions-runner plus the two CLIs garrison's CI gates need
# that the base image lacks: tmux (gate 4 drives a real tmux session) and
# unzip (oven-sh/setup-bun extracts bun with it).
# The first ARG *_VERSION drives the published image tag (see build-docker-images.yaml).
ARG RUNNER_VERSION=2.335.1

FROM ghcr.io/actions/actions-runner:${RUNNER_VERSION}

USER root
RUN apt-get update \
    && apt-get install -y --no-install-recommends tmux unzip \
    && rm -rf /var/lib/apt/lists/*
USER runner
