# Reference base image for agent-sandbox workloads that consume the NFS bin-cache
# (kubernetes/apps/pitower/ai/bin-cache/). Not used via `FROM` by claude-code-sandbox in this
# repo — the build pipeline builds each docker/<image> in an isolated context with no
# cross-image ordering guarantee, so claude-code-sandbox duplicates this setup directly
# instead of depending on this image's tag being published first (see bin-cache/README.md).
# Kept as the canonical, documented pattern for future sandboxes (e.g. flickerd-sandbox).
#
# The first ARG *_VERSION drives the published image tag (see build-docker-images.yaml).
ARG MISE_VERSION=2026.7.2

FROM debian:bookworm-slim

ARG MISE_VERSION
ARG TARGETARCH

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl jq tmux \
    && rm -rf /var/lib/apt/lists/*

# Pinned, checksum-verified mise binary — no install script, no unpinned curl|sh.
# mise names its linux amd64 release asset "x64", not "amd64".
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
# named after the tool — mise dispatches by argv[0], resolving the version from the mounted
# mise.toml (MISE_CONFIG_FILE) and the binary from MISE_DATA_DIR at runtime. No `mise reshim`
# against a live data dir needed, and no write to MISE_DATA_DIR ever happens.
# kubectl is intentionally excluded here — it's handled entirely by kubectl-wrapper.sh below,
# since a generic version-agnostic shim can't do the server-aware minor-version resolution.
RUN for tool in helm k9s argocd kustomize; do ln -s /usr/local/bin/mise "/usr/local/bin/${tool}"; done

COPY kubectl-wrapper.sh /usr/local/bin/kubectl
COPY verify-exec-mount.sh /usr/local/bin/verify-exec-mount
RUN chmod +x /usr/local/bin/kubectl /usr/local/bin/verify-exec-mount

# MISE_DATA_DIR is the read-only NFS mount — mise must only ever *select* an
# already-present version there, never attempt to install/download into it.
# The tree is arch-namespaced (linux-amd64/, linux-arm64/) because a single mise
# installs/ dir can't hold two architectures' binaries at once for the same
# tool@version; baking TARGETARCH in here means each platform's image variant
# (from the same multi-arch build) automatically points at its own matching subtree.
# Only linux-amd64 is actually populated today — pitower is entirely x86_64 (AMD
# Ryzen control planes, Intel workers), no arm64 hardware exists in this cluster.
ENV MISE_DATA_DIR=/mnt/nfs/bin-cache/linux-${TARGETARCH} \
    MISE_CACHE_DIR=/tmp/mise/cache \
    MISE_STATE_DIR=/tmp/mise/state \
    MISE_CONFIG_FILE=/etc/mise/mise.toml \
    MISE_TRUSTED_CONFIG_PATHS=/etc/mise \
    MISE_NOT_FOUND_AUTO_INSTALL=false \
    MISE_YES=true
