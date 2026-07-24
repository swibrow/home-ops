# Claude Code in a browser IDE (code-server), for running as an agent-sandbox workload.
# The first ARG *_VERSION drives the published image tag (see build-docker-images.yaml).
ARG CLAUDE_CODE_VERSION=2.1.167

FROM codercom/code-server:4.130.0

ARG CLAUDE_CODE_VERSION

USER root

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl gnupg git openssh-client less \
    && rm -rf /var/lib/apt/lists/*

# mise manages every CLI tool from here on (see mise.toml), installed system-wide
# under /opt+/etc so it's baked into the image and survives the /home/coder PVC mount.
ENV MISE_DATA_DIR=/opt/mise \
    MISE_CONFIG_DIR=/etc/mise \
    PATH="/opt/mise/shims:${PATH}"

RUN curl -fsSL https://mise.run | MISE_INSTALL_PATH=/usr/local/bin/mise sh

COPY mise.toml /etc/mise/config.toml
RUN mise install \
    && mise use --global claude-code@${CLAUDE_CODE_VERSION} \
    && claude --version

USER coder
ENV LANG=C.UTF-8
EXPOSE 8080
