# Infisical's official MCP server (@infisical/mcp) — an npx/Node stdio server with no
# upstream container image and no ToolHive registry entry, so we bake a pinned image
# here. build-docker-images.yaml derives the tag from the first ARG *_VERSION below
# and pushes ghcr.io/swibrow/infisical-mcp:<version> + :latest (amd64 + arm64).
FROM node:24-alpine

ARG INFISICAL_MCP_VERSION=0.0.23

RUN npm install -g @infisical/mcp@${INFISICAL_MCP_VERSION} \
    && npm cache clean --force

# bin is a bare "dist/index.js" string in package.json, so invoke the entry directly
# rather than relying on an ambiguous global command name. Speaks MCP over stdio.
ENTRYPOINT ["node", "/usr/local/lib/node_modules/@infisical/mcp/dist/index.js"]
