# Claude Code in a browser IDE (code-server), for running as an agent-sandbox workload.
# The first ARG *_VERSION drives the published image tag (see build-docker-images.yaml).
ARG CLAUDE_CODE_VERSION=2.1.167

FROM codercom/code-server:4.124.2

ARG CLAUDE_CODE_VERSION
ARG NODE_MAJOR=22

USER root

# git + node (for the claude CLI) + everyday agent tooling
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl gnupg git openssh-client jq ripgrep less \
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

USER coder
ENV LANG=C.UTF-8
EXPOSE 8080
