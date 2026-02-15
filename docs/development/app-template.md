# App Template

The [bjw-s app-template](https://github.com/bjw-s-labs/helm-charts/tree/main/charts/other/app-template) Helm chart is used for most applications in the cluster. It provides a standardized, opinionated structure for deploying containerized workloads.

**Current version**: 4.6.2

---

## Overview

The app-template chart abstracts common Kubernetes patterns (Deployments, Services, Ingress/HTTPRoutes, PVCs) into a declarative `values.yaml` format. Instead of writing raw Kubernetes manifests, you define controllers, containers, services, and routes.

```mermaid
flowchart TD
    Values[values.yaml] --> Chart[app-template chart]
    Chart --> Deploy[Deployment]
    Chart --> Svc[Service]
    Chart --> Route[HTTPRoute]
    Chart --> PVC[PersistentVolumeClaim]
    Chart --> CM[ConfigMap]
    Chart --> SA[ServiceAccount]
```

---

## Chart Reference

The chart is referenced in `kustomization.yaml` using OCI:

```yaml title="kustomization.yaml"
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: selfhosted
helmCharts:
  - name: app-template
    repo: oci://ghcr.io/bjw-s-labs/helm
    version: 4.6.2
    releaseName: my-app
    namespace: selfhosted
    valuesFile: values.yaml
```

---

## Values Structure

### Minimal Example

A minimal application with a single container, service, and HTTP route:

```yaml title="values.yaml"
controllers:
  my-app:
    annotations:
      reloader.stakater.com/auto: "true"
    containers:
      app:
        image:
          repository: ghcr.io/example/my-app
          tag: 1.0.0
        env:
          HTTP_PORT: 8080
        resources:
          requests:
            cpu: 10m
            memory: 64Mi
          limits:
            memory: 128Mi
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
      - my-app.example.com
    parentRefs:
      - name: envoy-external
        namespace: networking
        sectionName: https
```

---

## Controllers

Controllers define the workload type (Deployment by default) and its containers.

```yaml
controllers:
  my-app:
    # Optional: set replicas
    replicas: 1

    # Optional: set strategy
    strategy: Recreate

    # Annotations applied to the pod template
    annotations:
      reloader.stakater.com/auto: "true"

    # Pod-level settings
    pod:
      securityContext:
        runAsUser: 1000
        runAsGroup: 1000
        fsGroup: 1000

    containers:
      app:
        image:
          repository: ghcr.io/example/my-app
          tag: 1.0.0
        env:
          TZ: Europe/Zurich
          PORT: "8080"
        envFrom:
          - secretRef:
              name: my-app-secrets
        resources:
          requests:
            cpu: 10m
            memory: 64Mi
          limits:
            memory: 256Mi
```

### Multiple Containers (Sidecars)

```yaml
controllers:
  my-app:
    containers:
      app:
        image:
          repository: ghcr.io/example/my-app
          tag: 1.0.0
      sidecar:
        image:
          repository: ghcr.io/example/sidecar
          tag: 2.0.0
        args:
          - --config=/etc/sidecar/config.yaml
```

---

## Services

Define Kubernetes Services that expose container ports:

```yaml
service:
  app:
    controller: my-app  # Links to the controller (optional if name matches)
    ports:
      http:
        port: 8080
      metrics:
        port: 9090
```

### Multiple Services

```yaml
service:
  app:
    ports:
      http:
        port: 8080
  mqtt:
    type: LoadBalancer
    ports:
      mqtt:
        port: 1883
```

---

## Routes (HTTPRoute)

Routes configure Gateway API HTTPRoutes for ingress:

### External Route (Cloudflare-proxied)

```yaml
route:
  app:
    enabled: true
    hostnames:
      - my-app.example.com
    parentRefs:
      - name: envoy-external
        namespace: networking
        sectionName: https
```

### Internal Route (LAN/VPN only)

```yaml
route:
  app:
    enabled: true
    hostnames:
      - my-app.internal.example.com
    parentRefs:
      - name: envoy-internal
        namespace: networking
        sectionName: https
```

!!! note "Annotation Placement"
    The `cloudflare-proxied` annotation is read from the Route resource, not the Gateway. The `external-dns.alpha.kubernetes.io/target` annotation only works on Gateway resources, not on HTTPRoutes.

---

## Persistence

Define persistent storage for your application:

### PVC (Rook Ceph)

```yaml
persistence:
  data:
    enabled: true
    type: persistentVolumeClaim
    accessMode: ReadWriteOnce
    size: 5Gi
    storageClass: ceph-block
    globalMounts:
      - path: /data
```

### Existing PVC

```yaml
persistence:
  config:
    enabled: true
    type: persistentVolumeClaim
    existingClaim: my-app-config
    globalMounts:
      - path: /config
```

### EmptyDir

```yaml
persistence:
  tmp:
    type: emptyDir
    globalMounts:
      - path: /tmp
```

### ConfigMap Mount

```yaml
persistence:
  config:
    type: configMap
    name: my-app-config
    globalMounts:
      - path: /config/app.yaml
        subPath: app.yaml
        readOnly: true
```

### Secret Mount

```yaml
persistence:
  secrets:
    type: secret
    name: my-app-secrets
    globalMounts:
      - path: /secrets
        readOnly: true
```

---

## Health Probes

Always configure health probes for production workloads:

```yaml
probes:
  liveness:
    enabled: true
    custom: true
    spec:
      httpGet:
        path: /healthz
        port: 8080
      initialDelaySeconds: 10
      periodSeconds: 30
  readiness:
    enabled: true
  startup:
    enabled: true
    spec:
      failureThreshold: 30
      periodSeconds: 5
```

!!! tip "Startup Probes"
    Use startup probes with a high `failureThreshold` for applications that take a long time to initialize. This prevents the liveness probe from killing the container during startup.

---

## Environment Variables

### Static Environment Variables

```yaml
env:
  TZ: Europe/Zurich
  LOG_LEVEL: info
  HTTP_PORT: "8080"
```

### From Secrets

```yaml
envFrom:
  - secretRef:
      name: my-app-secrets
```

### From ConfigMap

```yaml
envFrom:
  - configMapRef:
      name: my-app-config
```

### Value From (Field Reference)

```yaml
env:
  POD_NAME:
    valueFrom:
      fieldRef:
        fieldPath: metadata.name
```

---

## Full Example

A complete example showing all common patterns:

```yaml title="values.yaml"
controllers:
  tandoor:
    annotations:
      reloader.stakater.com/auto: "true"
    containers:
      app:
        image:
          repository: ghcr.io/tandoorrecipes/recipes
          tag: 1.5.0
        env:
          TZ: Europe/Zurich
          DB_ENGINE: django.db.backends.postgresql
          POSTGRES_HOST: postgres-rw.cloudnative-pg.svc.cluster.local
          POSTGRES_PORT: "5432"
        envFrom:
          - secretRef:
              name: tandoor-secrets
        resources:
          requests:
            cpu: 50m
            memory: 256Mi
          limits:
            memory: 512Mi
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
      - recipes.example.com
    parentRefs:
      - name: envoy-external
        namespace: networking
        sectionName: https
persistence:
  data:
    enabled: true
    type: persistentVolumeClaim
    accessMode: ReadWriteOnce
    size: 2Gi
    storageClass: ceph-block
    globalMounts:
      - path: /opt/recipes/mediafiles
```
