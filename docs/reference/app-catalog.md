# App Catalog

Catalog of every application in `kubernetes/apps/pitower/`, organized by category. Each `{category}/{app}` directory is one ArgoCD Application (`pitower-{category}-{app}`) deployed into the namespace named after its category.

**Gateway** is the Envoy Gateway the app's HTTPRoutes attach to (`external` = public via the towonel tunnel, `internal` = home network and Tailscale only). **Chart** is the Helm chart rendered through kustomize `helmCharts` (including nested kustomizations), or `manifests` for plain YAML.

---

## Summary

| Category | Apps |
|:---------|:----:|
| [AI](#ai) | 17 |
| [Analytics](#analytics) | 1 |
| [ARC](#arc) | 2 |
| [Banking](#banking) | 5 |
| [Cert-Manager](#cert-manager) | 2 |
| [Database](#database) | 7 |
| [Dev](#dev) | 4 |
| [Home Automation](#home-automation) | 2 |
| [kopiur](#kopiur) | 2 |
| [Kube-System](#kube-system) | 4 |
| [KubeVirt and VMs](#kubevirt-and-vms) | 5 |
| [Media](#media) | 8 |
| [Monitoring](#monitoring) | 17 |
| [Networking](#networking) | 8 |
| [OpenEBS](#openebs) | 1 |
| [Renovate](#renovate) | 1 |
| [Rook Ceph](#rook-ceph) | 4 |
| [Second Brain](#second-brain) | 2 |
| [Security](#security) | 5 |
| [Self-Hosted](#self-hosted) | 13 |
| [System](#system) | 16 |
| [Workflows](#workflows) | 3 |
| [Workshop](#workshop) | 1 |
| [Personal Projects](#personal-projects) | 8 |
| **Total** | **138** |

---

## AI

| Name | Chart | Gateway | URL | Description |
|:-----|:------|:--------|:----|:------------|
| agent-sandbox | manifests | -- | -- | Kubernetes `agent-sandbox` controller and CRDs (vendored release) |
| agentgateway | agentgateway | internal | `llm.wibrow.dev`, `agentgateway.wibrow.dev` | LLM gateway: one OpenAI-compatible endpoint for local and hosted models |
| ai-training | manifests | -- | -- | Fine-tuning `train` WorkflowTemplate, its PVC and GPU claim ([Model Training](../applications/model-training.md)) |
| browser-use | app-template | internal | `browser-use.wibrow.dev`, `browser-vnc.wibrow.dev` | Browser automation agent with VNC view |
| comfyui | app-template | internal | `comfyui.wibrow.dev` | Node-based image generation UI |
| hermes | app-template | internal | `hermes.wibrow.dev`, `hermes-code.wibrow.dev` | Hermes Agent, config managed from this repo |
| iris | app-template | internal | `iris.wibrow.dev`, `iris-code.wibrow.dev` | Second Hermes Agent with self-managed config |
| llmkube | llmkube | -- | -- | LLM inference operator plus its Model/InferenceService resources |
| memini | memini | internal | `memini.wibrow.dev`, `memini-api.wibrow.dev` | Agent memory service on Postgres |
| mlflow | mlflow | internal | `mlflow.wibrow.dev` | Experiment tracking for fine-tunes and Claude Code traces; artifacts in Garage |
| open-terminal | app-template | -- | -- | Terminal backend for Open WebUI |
| open-webui | app-template | external | `chat.wibrow.dev` | Chat UI |
| paperless-rag | app-template | -- | -- | Syncs Paperless-ngx documents into an Open WebUI knowledge base |
| playwright | app-template | -- | -- | Headless browser for agents |
| searxng | app-template | -- | -- | Metasearch engine for agents |
| strata | app-template | internal | `strata.wibrow.dev` | Local LLM inference on the RTX 3090 Ti, scaled by KEDA |
| toolhive | toolhive-operator | external / internal | `mcp.wibrow.dev`, `mcp-api.wibrow.dev`, `mcp-internal.wibrow.dev` | MCP server operator and gateway |

---

## Analytics

| Name | Chart | Gateway | URL | Description |
|:-----|:------|:--------|:----|:------------|
| rybbit | app-template | external | `insights.wibrow.dev` | Self-hosted web analytics (backend, client, ClickHouse) |

---

## ARC

| Name | Chart | Gateway | URL | Description |
|:-----|:------|:--------|:----|:------------|
| controller | gha-runner-scale-set-controller | -- | -- | Actions Runner Controller |
| runners | gha-runner-scale-set | -- | -- | Self-hosted GitHub Actions runner scale sets (`home-ops` runners pinned to worker-07) |

---

## Banking

| Name | Chart | Gateway | URL | Description |
|:-----|:------|:--------|:----|:------------|
| actual | app-template | external | `actual.wibrow.dev` | Actual Budget |
| firefly | app-template | internal | `money.wibrow.dev` | Firefly III personal finance manager |
| firefly-importer | app-template | internal | `money-import.wibrow.dev` | Data importer for Firefly III |
| ghostfolio | app-template | internal | `portfolio.wibrow.dev` | Investment portfolio tracker |
| paperless | app-template | external | `paperless.wibrow.dev` | Paperless-ngx document management |

---

## Cert-Manager

| Name | Chart | Gateway | URL | Description |
|:-----|:------|:--------|:----|:------------|
| cert-manager | cert-manager | -- | -- | X.509 certificate management |
| issuers | manifests | -- | -- | Let's Encrypt ClusterIssuers (Cloudflare DNS-01) |

---

## Database

| Name | Chart | Gateway | URL | Description |
|:-----|:------|:--------|:----|:------------|
| barman-cloud-plugin | plugin-barman-cloud | -- | -- | CNPG backups to Garage S3 |
| clickhouse-operator | altinity-clickhouse-operator | -- | -- | ClickHouse operator |
| clusters | manifests | -- | -- | CNPG clusters (`shared`, `ai`, `immich`), object store, scheduled backups |
| clustersecretstore | manifests | -- | -- | `cnpg-secrets-database` ClusterSecretStore for database credentials |
| cnpg-operator | cloudnative-pg | -- | -- | CloudNativePG operator |
| dragonfly-operator | dragonfly-operator | -- | -- | Dragonfly (Redis-compatible) operator |
| tenants | manifests | -- | -- | Per-app Database, DatabaseRole, and credential ExternalSecret |

---

## Dev

| Name | Chart | Gateway | URL | Description |
|:-----|:------|:--------|:----|:------------|
| dev-desktop | manifests | -- (LB `10.20.10.231`) | -- | Arch/Hyprland desktop streamed over Sunshine, as an agent-sandbox `Sandbox` |
| forgejo | forgejo | external | `git.wibrow.dev` | Git forge (SSH on LB `10.20.10.230`) |
| herdr | app-template | internal | `term.wibrow.dev` | Web terminal (LB `10.20.10.232`) |
| propagit | app-template | external | `propagit.dev`, `propagit.wibrow.dev` | propagit web app |

---

## Home Automation

| Name | Chart | Gateway | URL | Description |
|:-----|:------|:--------|:----|:------------|
| frigate | app-template | internal | `frigate.wibrow.dev` | NVR with object detection (WebRTC on LB `10.20.10.235`) |
| home-assistant | manifests | external | `ha.wibrow.dev` | Route to Home Assistant OS, which runs on a separate Pi 4 on the iot VLAN |

---

## kopiur

| Name | Chart | Gateway | URL | Description |
|:-----|:------|:--------|:----|:------------|
| operator | kopiur | -- | -- | PVC snapshot backups with Kopia (namespace `kopiur-system`) |
| repository | manifests | -- | -- | `garage` ClusterRepository on Garage S3 |

---

## Kube-System

| Name | Chart | Gateway | URL | Description |
|:-----|:------|:--------|:----|:------------|
| cilium | cilium | internal | `hubble.wibrow.dev` | eBPF CNI, kube-proxy replacement, L2 + BGP announcements, Hubble |
| coredns | coredns | -- | -- | Cluster DNS |
| metrics-server | metrics-server | -- | -- | Resource metrics for HPA and `kubectl top` |
| multus | manifests | -- | -- | Thick Multus CNI and the `vlan20` NetworkAttachmentDefinition |

---

## KubeVirt and VMs

| Name | Chart | Gateway | URL | Description |
|:-----|:------|:--------|:----|:------------|
| kubevirt/kubevirt | manifests | -- | -- | KubeVirt operator and CR |
| kubevirt/cdi | manifests | -- | -- | Containerized Data Importer |
| vms/debian-test | manifests | -- | -- | Test VM |
| vms/dev | manifests | -- (LB `10.20.10.234`) | -- | Development VM |
| vms/omarchy | manifests | -- (LB `10.20.10.233`) | -- | Omarchy dev VM with the RTX 3090 Ti passed through |

---

## Media

| Name | Chart | Gateway | URL | Description |
|:-----|:------|:--------|:----|:------------|
| autobrr | app-template | internal | `autobrr.wibrow.dev` | Release automation for torrent/usenet indexers |
| immich | app-template | external | `photos.wibrow.dev` | Photo library (on `openebs-hostpath-media`) |
| jellyfin | app-template | external | `jellyfin.wibrow.dev` | Media server (LB `10.20.10.229`) |
| prowlarr | app-template | internal | `prowlarr.wibrow.dev` | Indexer manager for Sonarr/Radarr |
| qbittorrent | app-template | internal | `qbittorrent.wibrow.dev` | BitTorrent client |
| radarr | app-template | internal | `radarr.wibrow.dev` | Movie collection manager |
| sabnzbd | app-template | internal | `sabnzbd.wibrow.dev` | Usenet download client |
| sonarr | app-template | internal | `sonarr.wibrow.dev` | TV series collection manager |

---

## Monitoring

| Name | Chart | Gateway | URL | Description |
|:-----|:------|:--------|:----|:------------|
| blackbox-exporter | prometheus-blackbox-exporter | -- | -- | ICMP/TCP/HTTP probes of nodes, gateway, NAS, and endpoints |
| dozzle | app-template | internal | `dozzle.wibrow.dev` | Live container log viewer |
| fluent-bit | fluent-bit | -- | -- | Log collector, ships to VictoriaLogs |
| garage | manifests | -- | -- | Garage scrape config and alert rules |
| gatus | app-template | external | `up.wibrow.dev` | Uptime monitoring |
| grafana-operator | grafana-operator | external | `grafana.wibrow.dev` | Grafana Operator and Grafana instance |
| infra-health | manifests | -- | -- | Infrastructure alert rules |
| kube-prometheus-stack | kube-prometheus-stack | internal | `prometheus.wibrow.dev`, `alertmanager.wibrow.dev` | Prometheus, Alertmanager, exporters |
| ntfy | app-template | external | `ntfy.wibrow.dev` | Push notifications |
| ntfy-alertmanager | app-template | -- | -- | Alertmanager to ntfy bridge |
| nut-exporter | app-template | -- | -- | UPS telemetry from the NUT server |
| opentelemetry | opentelemetry-operator | external | `otlp.wibrow.dev` | OpenTelemetry operator and collector |
| smartctl-exporter | prometheus-smartctl-exporter | -- | -- | Disk SMART metrics |
| tempo | tempo | -- | -- | Distributed tracing backend |
| unpoller | app-template | -- | -- | UniFi network, device, and WAN metrics |
| victoria-logs | victoria-logs-single | -- | -- | Log storage |
| victoria-metrics | victoria-metrics-single | internal | `vm.wibrow.dev` | Long-term metrics storage |

---

## Networking

| Name | Chart | Gateway | URL | Description |
|:-----|:------|:--------|:----|:------------|
| envoy-gateway | gateway-helm | -- | -- | Gateway API implementation, `envoy-external` and `envoy-internal` gateways, fallback 404 route |
| external-dns | external-dns | -- | -- | DNS records in Cloudflare |
| external-dns-unifi | external-dns | -- | -- | DNS records on the UniFi gateway |
| kromgo | kromgo | external | `kromgo.wibrow.dev` | Cluster metric badges |
| netboot | app-template | -- | -- | PXE server on the untagged LAN (`192.168.0.248` via Multus) |
| openspeedtest | app-template | external | `openspeedtest.wibrow.dev` | Network speed test |
| tailscale | tailscale-operator | -- | -- | Tailscale operator and `pitower` subnet router / exit node |
| towonel-agent | app-template | -- | -- | towonel tunnel agent for public ingress |

---

## OpenEBS

| Name | Chart | Gateway | URL | Description |
|:-----|:------|:--------|:----|:------------|
| openebs | openebs | -- | -- | Local hostpath provisioner and the `-fast`, `-media`, `-models`, `-runners` StorageClasses |

---

## Renovate

| Name | Chart | Gateway | URL | Description |
|:-----|:------|:--------|:----|:------------|
| renovate-operator | renovate-operator | internal / external | `renovate.wibrow.dev`, `renovate-webhook.wibrow.dev` | Self-hosted Renovate |

---

## Rook Ceph

| Name | Chart | Gateway | URL | Description |
|:-----|:------|:--------|:----|:------------|
| operator | rook-ceph | -- | -- | Rook Ceph operator |
| cluster | rook-ceph-cluster | internal | `rook.wibrow.dev` | Ceph cluster (OSDs on worker-01..03), `ceph-block` StorageClass, dashboard |
| csi-drivers | ceph-csi-drivers | -- | -- | Ceph CSI drivers |
| add-ons | manifests | -- | -- | Dashboard add-ons |

---

## Second Brain

| Name | Chart | Gateway | URL | Description |
|:-----|:------|:--------|:----|:------------|
| affine | app-template | external | `affine.wibrow.dev` | AFFiNE knowledge base |
| couchdb | app-template | external | `obsidian.wibrow.dev` | CouchDB for Obsidian sync |

---

## Security

| Name | Chart | Gateway | URL | Description |
|:-----|:------|:--------|:----|:------------|
| aws-identity-webhook | amazon-eks-pod-identity-webhook | -- | -- | IAM roles for service accounts |
| crowdsec | crowdsec, envoy-proxy-bouncer | external | `crowdsec-lapi.wibrow.dev` | CrowdSec with an Envoy bouncer |
| external-secrets | external-secrets | -- | -- | External Secrets Operator and the Infisical ClusterSecretStores |
| kanidm | app-template | external | `idm.wibrow.dev` | Identity provider (OIDC/OAuth2, LDAP via `envoy-internal`) |
| rbac | manifests | -- | -- | ClusterRoleBindings for OIDC groups |

---

## Self-Hosted

| Name | Chart | Gateway | URL | Description |
|:-----|:------|:--------|:----|:------------|
| atuin | app-template | external | `atuin.wibrow.dev` | Shell history sync |
| cryptgeon | app-template | external | `secrets.wibrow.dev` | Encrypted secret sharing |
| echo-server | app-template | external | `echo.wibrow.dev` | HTTP echo server for testing |
| excalidraw | app-template | external | `draw.wibrow.dev` | Collaborative whiteboard |
| glance | app-template | external | `glance.wibrow.dev` | Dashboard / start page |
| homepage | app-template | external | `home.wibrow.dev` | Application dashboard |
| house-hunter | app-template | external | `house-hunter.wibrow.dev` | Property search aggregator |
| it-tools | app-template | external | `tools.wibrow.dev` | Developer utilities |
| mealie | app-template | external | `recipes.wibrow.dev` | Recipe manager |
| miniflux | app-template | external | `miniflux.wibrow.dev` | Minimalist RSS reader |
| n8n | app-template | external | `n8n.wibrow.dev`, `n8n-webhook.wibrow.dev` | Workflow automation |
| rrda | app-template | external | `rrda.wibrow.dev` | REST API for DNS lookups |
| whoami | app-template | external | `whoami.wibrow.dev` | Simple HTTP request echo |

---

## System

| Name | Chart | Gateway | URL | Description |
|:-----|:------|:--------|:----|:------------|
| dcgm-exporter | dcgm-exporter | -- | -- | NVIDIA GPU metrics |
| dra-driver-nvidia-gpu | dra-driver-nvidia-gpu | -- | -- | NVIDIA DRA driver (GPU sharing and VFIO passthrough) |
| etcd-defrag | manifests | -- | -- | Scheduled etcd defragmentation through the Talos API |
| garage | app-template | internal | `s3.wibrow.dev` | Garage S3 on worker-07's ZFS pools |
| headlamp | headlamp | internal | `headlamp.wibrow.dev` | Kubernetes UI with Kanidm SSO |
| intel-device-plugins | manifests | -- | -- | Intel device plugin operator and GPU plugin |
| keda | keda | -- | -- | Event-driven autoscaling |
| keda-http | keda-add-ons-http | -- | -- | KEDA HTTP add-on (scale to zero) |
| kubelet-csr-approver | kubelet-csr-approver | -- | -- | Approves kubelet serving certificate CSRs |
| node-feature-discovery | node-feature-discovery | -- | -- | Hardware feature labels |
| nvidia-power-limit | manifests | -- | -- | Caps the RTX 3090 Ti at 300 W |
| reloader | reloader | -- | -- | Restarts pods on ConfigMap/Secret changes |
| snapshot-controller | snapshot-controller | -- | -- | Volume snapshot controller |
| spegel | spegel | -- | -- | Peer-to-peer image registry mirror |
| terraform-state | manifests | -- | -- | ServiceAccount for Terraform state access |
| zfs-scrub | manifests | -- | -- | Monthly scrub of worker-07's ZFS pools |

---

## Workflows

| Name | Chart | Gateway | URL | Description |
|:-----|:------|:--------|:----|:------------|
| agentgateway-model-sync | manifests | -- | -- | CronWorkflow that syncs approved models into agentgateway |
| argo-events | argo-events | -- | -- | Event-driven triggers |
| argo-workflows | argo-workflows | internal | `argo-workflows.wibrow.dev` | Workflow engine |

---

## Workshop

| Name | Chart | Gateway | URL | Description |
|:-----|:------|:--------|:----|:------------|
| bambuddy | app-template | internal | `bambuddy.wibrow.dev` | Bambu Lab 3D printer manager |

---

## Personal Projects

Single-app categories for projects developed outside this repository.

| Category / Name | Chart | Gateway | URL |
|:----------------|:------|:--------|:----|
| flickerd/flickerd | manifests | -- | -- |
| garrison/garrison | garrison | external / internal | `garrison.wibrow.dev`, `garrison-hooks.wibrow.dev`, `garrison-alexa.wibrow.dev` |
| goat/goat | goat | external | `goat.wibrow.dev`, `goat-hooks.wibrow.dev` |
| pantry-system/pantry | manifests | external | `api.pantry.cloudsnacks.dev` |
| rackrat/rackrat | app-template | external | `rackrat.wibrow.dev` |
| rackrat/rackrat-comps | app-template | internal | `rackrat-comps.wibrow.dev` |
| trade-ops/trade-ops | trade-ops | external | `trade-ops.wibrow.dev` |
| trade-ops-dev/trade-ops | trade-ops | external | `trade-ops-dev.wibrow.dev` |

---

## Gateway Distribution

| Gateway | Apps |
|:--------|:----:|
| envoy-external | 40 |
| envoy-internal | 32 |
| None | 69 |

Some apps attach routes to both gateways, so the rows add up to more than 138. ArgoCD itself (`argocd.wibrow.dev`, external) is installed from `kubernetes/bootstrap/` and is not counted.
