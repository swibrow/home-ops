# syntax=docker/dockerfile:1
# Source lives next to this file; bump the version to publish a new tag.
ARG FAMILY_HOME_VERSION=0.2.10

FROM node:24.22.2-slim AS build
WORKDIR /app
RUN npm install --global bun@1.3.14
COPY package.json bun.lock ./
RUN bun install --frozen-lockfile --ignore-scripts
COPY . .
# better-sqlite3 (pulled in by @actual-app/api) needs its prebuilt binary for this node ABI.
RUN bun run build \
    && rm -rf node_modules \
    && bun install --production --frozen-lockfile --ignore-scripts \
    && npm rebuild better-sqlite3

FROM node:24.22.2-slim
ENV NODE_ENV=production HOST=0.0.0.0 PORT=8080 CONFIG_PATH=/config/config.yaml ACTUAL_DATA_DIR=/tmp/actual
WORKDIR /app
COPY --from=build /app/package.json ./
COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/dist ./dist
USER 2000:2000
EXPOSE 8080
CMD ["node", "dist/server/entry.mjs"]
