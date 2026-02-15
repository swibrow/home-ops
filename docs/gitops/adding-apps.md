---
title: Adding Apps
---

# Adding a New Application

Adding a new application to the cluster requires no ArgoCD configuration changes. Thanks to the [ApplicationSet](application-sets.md) pattern, creating a directory in the right place is all it takes.

---

## Quick Start

To deploy a new application, you need to:

1. Choose the appropriate category for your app.
2. Create a directory under `pitower/kubernetes/apps/<category>/<app-name>/`.
3. Add a `kustomization.yaml` and (optionally) a `values.yaml`.
4. Push to `main`.
5. ArgoCD auto-discovers and syncs the new app.

```mermaid
flowchart LR
    A[Create directory\nand manifests] --> B[Push to main]
    B --> C[ApplicationSet\ndetects new dir]
    C --> D[Application\ncreated]
    D --> E[Resources synced\nto cluster]

    style A fill:#7c3aed,color:#fff
    style C fill:#18b7be,color:#fff
    style D fill:#18b7be,color:#fff
    style E fill:#326ce5,color:#fff
```

---

## Step-by-Step Guide

### 1. Choose a Category

Pick the category that best fits your application:

| Category | Use For |
|:---------|:--------|
| `ai` | AI and machine learning workloads |
| `banking` | Financial tools and services |
| `cert-manager` | TLS certificate resources |
| `cloudnative-pg` | PostgreSQL clusters and backups |
| `home-automation` | Home Assistant, Zigbee2MQTT, MQTT brokers |
| `kube-system` | Core cluster components |
| `media` | Jellyfin, *arr apps, downloaders |
| `monitoring` | Prometheus, Grafana, Loki, alerting |
| `networking` | Envoy Gateway, Cilium, DNS, tunnels |
| `openebs` | Local PV storage |
| `rook-ceph` | Distributed storage |
| `security` | Authentication, secrets, certificates |
| `selfhosted` | General self-hosted applications |
| `system` | System-level utilities |

!!! tip "When in Doubt"
    If your app does not clearly fit a category, `selfhosted` is a good default for general-purpose applications.

### 2. Create the Directory

```bash
mkdir -p pitower/kubernetes/apps/<category>/<app-name>
```

The directory name becomes the app name in ArgoCD. Choose a name that is lowercase, uses hyphens for separation, and is descriptive:

- `echo-server` (good)
- `home-assistant` (good)
- `myApp` (bad -- use lowercase with hyphens)

### 3. Create the Manifests

Most applications in the cluster use the [bjw-s app-template](https://github.com/bjw-s-labs/helm-charts) Helm chart (v4.6.2) inflated through Kustomize. This pattern requires two files:

=== "kustomization.yaml"

    ```yaml
    ---
    apiVersion: kustomize.config.k8s.io/v1beta1
    kind: Kustomization
    namespace: <category>
    helmCharts:
      - name: app-template
        repo: oci://ghcr.io/bjw-s-labs/helm
        version: 4.6.2
        releaseName: <app-name>
        namespace: <category>
        valuesFile: values.yaml
    ```

=== "values.yaml"

    ```yaml
    controllers:
      <app-name>:
        containers:
          app:
            image:
              repository: <image-repo>
              tag: <image-tag>
            env:
              # Environment variables
              TZ: Europe/Zurich
            resources:
              requests:
                cpu: 10m
                memory: 64Mi
              limits:
                memory: 256Mi
            probes:
              liveness:
                enabled: true
              readiness:
                enabled: true
    service:
      app:
        ports:
          http:
            port: 8080
    route:
      app:
        enabled: true
        hostnames:
          - <app-name>.example.com
        parentRefs:
          - name: envoy-internal
            namespace: networking
            sectionName: https
    ```

!!! info "Gateway Selection"
    Choose the appropriate gateway in `parentRefs` based on how the app should be accessed:

    | Gateway | Use Case |
    |:--------|:---------|
    | `envoy-external` | Accessible via Cloudflare tunnel (`*.example.com` proxied) |
    | `envoy-internal` | Internal-only access (VPN/LAN via `internal.example.com`) |

### 4. Complete Example: echo-server

Here is a real example from the cluster -- the `echo-server` app in the `selfhosted` category.

**Directory structure:**

```
pitower/kubernetes/apps/selfhosted/echo-server/
├── kustomization.yaml
└── values.yaml
```

**kustomization.yaml:**

```yaml
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: selfhosted
helmCharts:
  - name: app-template
    repo: oci://ghcr.io/bjw-s-labs/helm
    version: 4.6.2
    releaseName: echo-server
    namespace: selfhosted
    valuesFile: values.yaml
```

**values.yaml:**

```yaml
controllers:
  echo-server:
    annotations:
      reloader.stakater.com/auto: "true"
    containers:
      app:
        image:
          repository: ghcr.io/mendhak/http-https-echo
          tag: 39
        env:
          HTTP_PORT: 8080
          LOG_WITHOUT_NEWLINE: "true"
          LOG_IGNORE_PATH: /healthz
        resources:
          requests:
            cpu: 5m
            memory: 32Mi
          limits:
            memory: 64Mi
        probes:
          liveness:
            enabled: true
          readiness:
            enabled: true
          startup:
            enabled: true
            spec:
              failureThreshold: 30
              periodSeconds: 5
service:
  app:
    ports:
      http:
        port: 8080
route:
  app:
    enabled: true
    hostnames:
      - echo.example.com
    parentRefs:
      - name: envoy-external
        namespace: networking
        sectionName: https
```

This produces an ArgoCD Application named `selfhosted-echo-server` that deploys into the `selfhosted` namespace.

### 5. Push and Verify

```bash
git add pitower/kubernetes/apps/<category>/<app-name>/
git commit -m "feat(<category>): add <app-name>"
git push origin main
```

After pushing, verify in ArgoCD:

```bash
# Check that the Application was created
argocd app list -l app.kubernetes.io/name=<app-name>

# Watch the sync status
argocd app get <category>-<app-name>

# Or use kubectl
kubectl get applications -n argocd <category>-<app-name>
```

---

## Advanced Patterns

### Apps with Extra Resources

Some apps need additional Kubernetes resources beyond what the Helm chart provides (certificates, gateway routes, etc.). Add them as extra files and reference them in `kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: networking
resources:
  - certificate.yaml
  - external.yaml
  - internal.yaml
helmCharts:
  - name: app-template
    repo: oci://ghcr.io/bjw-s-labs/helm
    version: 4.6.2
    releaseName: envoy-gateway
    namespace: networking
    valuesFile: values.yaml
```

### Apps Without Helm

If your app does not use a Helm chart, you can use plain manifests with Kustomize:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: <category>
resources:
  - deployment.yaml
  - service.yaml
  - httproute.yaml
```

### Apps with SOPS Secrets

For apps that need encrypted secrets, add the SOPS-encrypted file and reference it in `kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: <category>
resources:
  - secret.sops.yaml
helmCharts:
  - name: app-template
    # ...
```

!!! warning "Never Commit Plaintext Secrets"
    Always encrypt secrets with SOPS before committing. See the [SOPS documentation](../security/sops.md) for details.

---

## Removing an Application

To remove an application from the cluster:

1. Delete the app directory:
    ```bash
    rm -rf pitower/kubernetes/apps/<category>/<app-name>
    ```
2. Push to `main`:
    ```bash
    git add -A && git commit -m "feat(<category>): remove <app-name>"
    git push origin main
    ```
3. The ApplicationSet detects the missing directory and deletes the Application.
4. The `resources-finalizer.argocd.argoproj.io` finalizer ensures all managed resources are cleaned up from the cluster.

---

## Checklist

Use this checklist when adding a new app:

- [ ] Directory created at `pitower/kubernetes/apps/<category>/<app-name>/`
- [ ] `kustomization.yaml` with correct `namespace` and chart configuration
- [ ] `values.yaml` with image, resources, probes, and service defined
- [ ] HTTPRoute configured with the correct gateway (`envoy-external` or `envoy-internal`)
- [ ] Resource requests and limits set appropriately
- [ ] Secrets encrypted with SOPS (if applicable)
- [ ] Pushed to `main` and verified in ArgoCD UI
