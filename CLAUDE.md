# Home-Ops

Kubernetes home lab GitOps repository.

## Stack

- **Talos Linux** — immutable Kubernetes OS
- **ArgoCD** — GitOps continuous delivery
- **Cilium** — CNI with L2 announcements (LoadBalancer IPs: 192.168.0.220-239)
- **Envoy Gateway** — ingress (external/internal/direct gateways)
- **CloudNativePG** — PostgreSQL operator
- **Volsync** — PVC backup to S3
- **External Secrets** — Infisical + CNPG ClusterSecretStores
- **External DNS** — Cloudflare DNS management

## Domain

`wibrow.dev` via Cloudflare

## App Structure

```
kubernetes/apps/{cluster}/{category}/{app}/
├── kustomization.yaml   # namespace, volsync component, helmCharts generator
├── values.yaml          # app-template helm values
└── externalsecret.yaml  # optional: Infisical + CNPG secrets
```

- One ApplicationSet per cluster using git directory generator: `kubernetes/apps/{cluster}/*/*`
- App naming: `{cluster}-{category}-{app}` from path segments
- Namespace derived from category
- Helm chart: `app-template` (bjw-s-labs) v4.6.2 via `oci://ghcr.io/bjw-s-labs/helm`

## Key Conventions

- **Routes** use Gateway API (`HTTPRoute`) with `parentRefs` to `envoy-internal`, `envoy-external`, or `envoy-direct` in namespace `networking`, sectionName `https`
- **Databases** use CNPG clusters defined in `kubernetes/apps/pitower/cloudnative-pg/cluster/cluster.yaml`, accessed via `cnpg-secrets` ClusterSecretStore
- **App secrets** stored in Infisical at `/category/app/SECRET_NAME`
- **Volsync** backups via reusable kustomize component at `kubernetes/components/volsync`, configured per-app with `volsync-config` ConfigMap
- **Timezone**: `Europe/Zurich`
- **Reloader** annotation `reloader.stakater.com/auto: "true"` on controllers that consume secrets

## Analytics

[Rybbit](https://insights.wibrow.dev) (self-hosted) at `kubernetes/apps/pitower/analytics/rybbit/`. Backend + client + ClickHouse; tracking script is served at `https://insights.wibrow.dev/api/script.js`.

To track a site, embed the snippet in the page `<head>` (get `data-site-id` from the Rybbit dashboard):

```html
<script src="https://insights.wibrow.dev/api/script.js" data-site-id="<id>" defer></script>
```

- **Per-app (preferred)**: use the app's own injection hook. Homepage exposes `custom.js` (`<Script src="/api/config/custom.js"/>`) — drop a loader in the configmap and mount it at `/app/config/custom.js` (see `apps/pitower/selfhosted/homepage/`). Same-origin, client-side, no proxy tricks.
- **Gateway-wide injection** (only when the app has no hook): attach an `EnvoyExtensionPolicy` (Lua, EG v1.8.0) to the target `HTTPRoute` under `networking`. The Lua `envoy_on_response` checks `content-type` for `text/html` and inserts the `<script>` before `</head>` via `body:setBytes()`. **Caveat: compression breaks it** — browsers send `Accept-Encoding: br/gzip`, so the Lua sees compressed bytes and the `</head>` match silently fails (curl without `--compressed` misleadingly works). You'd have to strip `Accept-Encoding` on the request path, losing compression. Prefer the app-native hook.

## Bootstrap

- ArgoCD + ApplicationSets at `kubernetes/bootstrap/`
- CNPG operator + clusters at `kubernetes/apps/pitower/cloudnative-pg/`

## Infrastructure

- Cluster: `pitower`, control plane at 192.168.0.201
- Talos configs: `kubernetes/talos/pitower/` — lifecycle managed with [topf](https://github.com/postfinance/topf) (`topf.yaml` + layered patches in `all/`, `control-plane/`, `node/<host>/`; secrets stay SOPS-encrypted, decrypted by topf via the repo age key). `talosctl` only for diagnostics.
- Terraform: `terraform/` (AWS, Cloudflare, etc.)

## Task Tracking

All TODOs, planned work, and follow-ups for this repo are tracked on the GitHub project board: <https://github.com/users/swibrow/projects/4>.

- Do not scatter TODOs in code comments, issues, or memory — create/update items on the board.
- Use `gh project` CLI (owner `swibrow`, project number `4`) to list/add/update items.
- Requires `project` scope: `gh auth refresh -s project` if missing.
