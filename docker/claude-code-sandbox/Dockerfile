# Claude Code in a browser IDE (code-server), for running as an agent-sandbox workload.
# The first ARG *_VERSION drives the published image tag (see build-docker-images.yaml).
ARG CLAUDE_CODE_VERSION=2.1.167

FROM codercom/code-server:4.129.0

ARG CLAUDE_CODE_VERSION
ARG NODE_MAJOR=22
ARG MISE_VERSION=2026.7.2
ARG TARGETARCH

USER root

# git + node (for the claude CLI) + tmux (not servable from the mise bin-cache, see
# docker/agent-sandbox-base/Dockerfile) + everyday agent tooling
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl gnupg git openssh-client jq ripgrep less tmux \
    && mkdir -p /etc/apt/keyrings \
    && curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
       | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_${NODE_MAJOR}.x nodistro main" \
       > /etc/apt/sources.list.d/nodesource.list \
    && apt-get update && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

# Claude Code, baked into the image so sandbox resume is instant (no npm reinstall).
RUN npm install -g @anthropic-ai/claude-code@${CLAUDE_CODE_VERSION} \
    && claude --version

# NFS bin-cache (kubernetes/apps/pitower/ai/bin-cache/) wiring — pinned, checksum-verified
# mise binary. No install script, no unpinned curl|sh. mise names its linux amd64 release
# asset "x64", not "amd64".
RUN set -eu; \
    case "${TARGETARCH}" in \
      arm64) MISE_ASSET=arm64; MISE_SHA256=c10333ee9666f80bc09ef7f391884876fb25fedeed3844f57c48370fe308a7cf ;; \
      amd64) MISE_ASSET=x64; MISE_SHA256=83d88443231ba3b1c061cd4004c5b62848c8580a36e786a4145481e18d6e1402 ;; \
      *) echo "unsupported TARGETARCH: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    curl -fsSLo /usr/local/bin/mise "https://github.com/jdx/mise/releases/download/v${MISE_VERSION}/mise-v${MISE_VERSION}-linux-${MISE_ASSET}"; \
    echo "${MISE_SHA256}  /usr/local/bin/mise" | sha256sum -c -; \
    chmod +x /usr/local/bin/mise

# Pre-generated mise shims: a real mise shim is just a symlink to the mise binary itself,
# named after the tool — mise dispatches by argv[0] and resolves version + binary at runtime
# from the mounted mise.toml / NFS mount, never writing to either. kubectl is excluded here;
# it's handled by kubectl-wrapper.sh, which does server-aware minor-version resolution that a
# generic shim can't.
RUN for tool in helm k9s argocd kustomize; do ln -s /usr/local/bin/mise "/usr/local/bin/${tool}"; done

COPY kubectl-wrapper.sh /usr/local/bin/kubectl
COPY verify-exec-mount.sh /usr/local/bin/verify-exec-mount
RUN chmod +x /usr/local/bin/kubectl /usr/local/bin/verify-exec-mount

# MISE_DATA_DIR is the read-only NFS mount — mise must only ever *select* an already-present
# version there, never attempt to install/download into it. The tree is arch-namespaced
# (linux-amd64/, linux-arm64/) since a single mise installs/ dir can't hold two
# architectures' binaries for the same tool@version; baking TARGETARCH here means this
# image's per-platform variant automatically points at its own matching subtree. Only
# linux-amd64 is actually populated today — pitower is entirely x86_64.
ENV MISE_DATA_DIR=/mnt/nfs/bin-cache/linux-${TARGETARCH} \
    MISE_CACHE_DIR=/tmp/mise/cache \
    MISE_STATE_DIR=/tmp/mise/state \
    MISE_CONFIG_FILE=/etc/mise/mise.toml \
    MISE_TRUSTED_CONFIG_PATHS=/etc/mise \
    MISE_NOT_FOUND_AUTO_INSTALL=false \
    MISE_YES=true

USER coder
ENV LANG=C.UTF-8
EXPOSE 8080
