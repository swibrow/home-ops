---
title: Self-Hosted Applications
---

# Self-Hosted Applications

The `selfhosted` namespace contains productivity tools, dashboards, and utility services. All are deployed with the bjw-s app-template Helm chart and attach to `envoy-external`.

## Application Catalog

| App | Description | URL | Data |
|:----|:------------|:----|:-----|
| **Atuin** | Shell history sync server | `atuin.wibrow.dev` | PostgreSQL (`shared`) |
| **Cryptgeon** | Encrypted, view-once notes and files | `secrets.wibrow.dev` | Dragonfly |
| **Echo Server** | HTTP request debugging | `echo.wibrow.dev` | -- |
| **Excalidraw** | Collaborative whiteboard | `draw.wibrow.dev` | -- |
| **Glance** | Dashboard with feeds and widgets | `glance.wibrow.dev` | -- |
| **Homepage** | Kubernetes-aware application dashboard | `home.wibrow.dev` | -- |
| **House Hunter** | Property search aggregator | `house-hunter.wibrow.dev` | PostgreSQL (`shared`) |
| **IT Tools** | Developer utilities in the browser | `tools.wibrow.dev` | -- |
| **Mealie** | Recipe management and meal planning | `recipes.wibrow.dev` | PVC, kopiur backups |
| **Miniflux** | Minimalist RSS/Atom reader | `miniflux.wibrow.dev` | PostgreSQL (`shared`) |
| **n8n** | Workflow automation | `n8n.wibrow.dev` | PVC, kopiur backups |
| **RRDA** | REST API for DNS lookups | `rrda.wibrow.dev` | -- |
| **Whoami** | Minimal HTTP debugging endpoint | `whoami.wibrow.dev` | -- |

PostgreSQL apps are tenants on the `shared` CNPG cluster and use the `cnpg-db-shared` component; see [Databases](../databases/index.md).

---

## Application Details

### Atuin

[Atuin](https://atuin.sh/) syncs encrypted shell history between machines.

- **Image**: `ghcr.io/atuinsh/atuin`
- **Database**: tenant `atuin` on the `shared` cluster
- **Access control**: an Envoy Gateway `SecurityPolicy` on the `atuin` HTTPRoute checks an `X-API-Key` header against the `atuin-apikeys` Secret, since the CLI client cannot follow an OIDC redirect

### Cryptgeon

[Cryptgeon](https://github.com/cupcakearmy/cryptgeon) provides encrypted, self-destructing notes and file sharing. Messages are encrypted client-side.

- **Image**: `cupcakearmy/cryptgeon`, plus a `static-web-server` container for custom branding
- **Storage**: a `Dragonfly` instance (`cryptgeon-dragonfly`) managed by the Dragonfly operator

### Echo Server

[HTTP Echo Server](https://github.com/mendhak/docker-http-https-echo) returns request headers, body, and metadata. Useful for debugging gateway routing, TLS termination, and header injection.

- **Image**: `ghcr.io/mendhak/http-https-echo`
- **Scale to zero**: a KEDA `ScaledObject` (min 0, max 1) with an HTTP add-on `InterceptorRoute` starts it on demand

### Excalidraw

[Excalidraw](https://excalidraw.com/) is a collaborative whiteboard for sketching diagrams.

- **Image**: `docker.io/excalidraw/excalidraw:latest` (digest pinned)
- **Storage**: `emptyDir` only (stateless)

### Glance

[Glance](https://github.com/glanceapp/glance) is a dashboard with widgets for RSS feeds, weather, bookmarks, and monitoring.

- **Image**: `docker.io/glanceapp/glance`
- **Configuration**: ConfigMap mounted as the Glance config

### Homepage

[Homepage](https://gethomepage.dev/) is a Kubernetes-aware application dashboard.

- **Image**: `ghcr.io/gethomepage/homepage`
- **Configuration**: ConfigMap with bookmarks, services, settings and widgets, plus `custom.js`, which loads the [Rybbit](https://insights.wibrow.dev) tracking script
- **RBAC**: ServiceAccount with cluster read permissions for service discovery

> [!TIP]
> **Keeping it in sync**
>
> The `sync-homepage` skill (`.claude/skills/sync-homepage`) compares the Homepage config with the apps deployed in the cluster and reports stale or missing entries.

### House Hunter

[House Hunter](https://github.com/swibrow/house-hunter) is a custom property search aggregator.

- **Image**: `ghcr.io/swibrow/house-hunter:latest`
- **Database**: tenant `house_hunter` on the `shared` cluster

### IT Tools

[IT Tools](https://github.com/sharevb/it-tools) is a collection of developer utilities (encoders, converters, generators).

- **Image**: `ghcr.io/sharevb/it-tools`

### Mealie

[Mealie](https://mealie.io/) is a recipe manager and meal planner.

- **Image**: `ghcr.io/mealie-recipes/mealie`
- **Storage**: PVC `mealie-data` at `/app/data` via the `pvc` component, backed up by `kopiur` (mover runs as uid 911 to match the app)
- **Auth**: OIDC client secret from Infisical

### Miniflux

[Miniflux](https://miniflux.app/) is a minimalist RSS feed reader.

- **Image**: `ghcr.io/miniflux/miniflux` (distroless)
- **Database**: tenant `miniflux` on the `shared` cluster
- **Auth**: OIDC via Kanidm (`idm.wibrow.dev`)
- **Polling**: every 15 minutes using the entry frequency scheduler

### n8n

[n8n](https://n8n.io/) is a workflow automation platform with a visual editor.

- **Image**: `ghcr.io/n8n-io/n8n`
- **Storage**: PVC `n8n` at `/home/node/.n8n` via the `pvc` component, backed up by `kopiur`

> [!NOTE]
> **Dual Routes**
>
> n8n has two HTTPRoutes on `envoy-external`: `n8n.wibrow.dev` for the UI and `n8n-webhook.wibrow.dev` for webhook callbacks.

### RRDA

[RRDA](https://github.com/swibrow/rrda) is a REST API for DNS record lookups.

- **Image**: `ghcr.io/cloudsnacks/rrda` (built in [cloudsnacks/containers](https://github.com/cloudsnacks/containers))
- **Sidecar**: `adguard/dnsproxy` forwarding to Cloudflare over DNS-over-HTTPS (`1.1.1.1`, `1.0.0.1`)

> [!NOTE]
> **DoH Sidecar**
>
> The dnsproxy sidecar sends queries over HTTPS to avoid the UniFi gateway's interception of plain DNS on port 53. See [DNS Management](../../networking/dns-management.md).

### Whoami

[Whoami](https://github.com/traefik/whoami) is a tiny HTTP server that returns connection and request information.

- **Image**: `docker.io/traefik/whoami`
