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

`pitower.link` via Cloudflare

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

## Bootstrap

- ArgoCD + ApplicationSets at `kubernetes/bootstrap/`
- CNPG operator + clusters at `kubernetes/apps/pitower/cloudnative-pg/`

## Infrastructure

- Cluster: `pitower`, control plane at 192.168.0.201
- Talos configs: `kubernetes/talos/pitower/`
- Terraform: `terraform/` (AWS, Cloudflare, etc.)
