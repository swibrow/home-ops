# Populate-plane image for the NFS binary cache (kubernetes/apps/pitower/ai/bin-cache/).
# Runs `mise install` against the committed mise.toml/mise.lock, verifying every download's
# checksum before writing to the shared NFS mount. This is the only image in the cache with
# egress and write access.
# The first ARG *_VERSION drives the published image tag (see build-docker-images.yaml).
ARG MISE_VERSION=2026.7.2

FROM debian:bookworm-slim

ARG MISE_VERSION
ARG TARGETARCH

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl \
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

# Matches the runAsUser/Group the populate Job/CronJob run as (kubernetes/apps/pitower/ai/bin-cache/),
# reusing the UID already proven to write successfully against this NFS server (see sonarr/radarr/jellyfin).
RUN groupadd -g 2000 populate && useradd -u 2000 -g 2000 -m -d /home/populate -s /bin/sh populate

USER populate
ENV HOME=/tmp
