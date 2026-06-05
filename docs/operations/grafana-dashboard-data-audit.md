# Grafana Dashboard Data Audit

Audit of all 54 Grafana dashboards on `pitower`, run 2026-06-03. Method: for every
panel, the underlying PromQL metric names were extracted and tested for existence in
the Prometheus / VictoriaMetrics datasources (`count(<metric>)` instant query). A panel
is **dead** when *all* its metrics are absent, **partial** when some are absent.
Log-based (VictoriaLogs) panels can't be metric-tested and are flagged for manual check.

Datasources: `prometheus` (default), `victoriametrics`, `victorialogs`.

Work through the priority buckets below. Healthy dashboards are listed at the bottom.

---

## Changes made (2026-06-03, uncommitted)

1. `grafana/values.yaml` — node-exporter-full dashboard rev 37 → 45.
2. `kube-prometheus-stack/values.yaml` — removed the `go_.*` drop from the default
   scrapeClass (restores Goroutines panels on API server / Controller-Manager /
   Kubelet / Scheduler / VictoriaLogs).
3. `kube-prometheus-stack/values.yaml` — `kubeEtcd` now scrapes `:2381` over `http`.
4. `controlplane.patch` — added `etcd.extraArgs.listen-metrics-urls`,
   `controllerManager.extraArgs.bind-address: 0.0.0.0`,
   `scheduler.extraArgs.bind-address: 0.0.0.0`.

**To apply the Talos change** (item 4) — requires home-network/VPN + talosctl:
```
cd kubernetes/talos/pitower
just config && just patch          # regenerate machine configs from the patch
# apply to the CURRENT control-plane nodes — worker-01/02/03 = 10.20.10.1/2/3
# (note `just apply-controlplanes` targets are stale):
talosctl apply-config --nodes 10.20.10.1 --file ./clusterconfig/<cp>.yaml   # etc.
```
This rolls etcd/scheduler/controller-manager static pods (one CP at a time — safe).
Items 1–3 ship via ArgoCD on git push.

**Still pending live check** (blocked on cluster access): ~~Ceph mgr ServiceMonitor~~
(resolved 2026-06-05 — see P1 Ceph/Rook below), Cilium-agent ServiceMonitor.

---

## Root-cause analysis (2026-06-03)

Verified via Prometheus (`up` by job) + repo config. Live `kubectl` diagnosis was
blocked — the API VIP `10.20.10.0:6443` was unreachable from the workstation (needs
home network/VPN). Items marked **[needs live check]** await on-network inspection.

| Symptom | Root cause | Determinable fix |
|---|---|---|
| `go_*` absent cluster-wide (Goroutines dead on 5 dashboards) | **Intentional** — `prometheusSpec.scrapeClasses[default].metricRelabelings` drops `go_.*` (`kube-prometheus-stack/values.yaml:211`). Overrides the per-component `keep go` lists (now dead config). | Decision needed — remove the drop to restore, or accept (cardinality). |
| etcd 15/16 dead — no `etcd` job exists | Talos etcd metrics not exposed. `controlplane.patch` has no `cluster.etcd.extraArgs.listen-metrics-urls`. `kubeEtcd.endpoints` point at `:2381` but nothing listens. | Add `etcd.extraArgs: {listen-metrics-urls: http://0.0.0.0:2381}` to `controlplane.patch`; ensure kubeEtcd scrapes `:2381` http. Requires `talosctl apply` to 3 CPs. |
| Scheduler 17/18 + Controller-Manager (audit false-positive) — `up==0` for all 3 each | Components bind metrics to `127.0.0.1`; no `bind-address` override in `controlplane.patch`. | Add `scheduler.extraArgs` + `controllerManager.extraArgs` `bind-address: 0.0.0.0`. Requires `talosctl apply`. |
| Ceph 64 panels dead — no `ceph`/`rook` job | **✅ RESOLVED (2026-06-05).** Operator chart `monitoring.enabled: false` vs cluster chart `true` → operator SA forbidden from creating ServiceMonitors. | Set operator `monitoring.enabled: true` (commit `939a8ce1`) + one operator reconcile. Both SMs now up, all `ceph_*` metrics flowing. |
| Cilium Metrics 70/70 dead — only `cilium-operator` job (no agent) | Agent config `cni/values.yaml` has `prometheus.enabled: true` + serviceMonitor, but no `cilium-agent` job is scraped — likely drift between the Talos-bootstrap CNI values and the live install. | **[needs live check]** — confirm the agent metrics Service + ServiceMonitor exist on the live cluster. |

> Note: `serviceMonitorSelectorNilUsesHelmValues: false` is set, so Prometheus selects
> *all* ServiceMonitors cluster-wide — if the Ceph/Cilium-agent SMs existed, they'd be
> scraped. Their absence from `up` means the SMs themselves aren't present.

---

## P1 — Real gaps (data *should* be here; a scrape target/exporter is missing)

### Ceph / Rook — ✅ RESOLVED (2026-06-05)
~~No `ceph_*` metric exists in **either** Prometheus or VictoriaMetrics. The Rook-Ceph
mgr Prometheus exporter is not being scraped at all.~~
- ~~**Ceph - Cluster** (`r6lloPJmz`): 47/59 panels dead (every ceph_* panel; only node_* + ALERTS render)~~
- ~~**Ceph - OSD (Single)** (`Fj5fAfzik123`): 12/12 dead~~
- ~~**Ceph - Pools** (`-gtf0Bzik`): 5/5 dead~~
- **Root cause:** the rook-ceph **operator** chart had `monitoring.enabled: false` while the
  **cluster** chart had `monitoring.enabled: true`. So the operator's `rook-ceph-global`
  ClusterRole lacked `monitoring.coreos.com` rules and the operator SA (`rook-ceph-system`)
  was *forbidden* from creating the `rook-ceph-mgr` / `rook-ceph-exporter` ServiceMonitors
  (constant `nodedaemon: ... service monitor could not be enabled ... forbidden` errors).
  The mgr `:9283/metrics` endpoint was serving data the whole time — nothing was scraping it.
- **Fix:** set `monitoring.enabled: true` in `rook-ceph/operator/values.yaml` (commit `939a8ce1`),
  which grants the SM/PrometheusRule RBAC. The exporter SM self-healed on the next nodedaemon
  loop; the `rook-ceph-mgr` SM was created after one operator reconcile (`rollout restart`).
- **Verified:** both SMs present, `rook-ceph-exporter` 5/5 + `rook-ceph-mgr` 1/1 targets up,
  `ceph_health_status=0` (HEALTH_OK), 3 OSDs / 3 mon quorum / 2 pools / ~1.54 TB capacity all reporting.

### etcd — `c2f4e12cdf69feb95caa41a5a1b423d9`
15/16 panels dead. No `etcd_*` or `grpc_server_*` metrics scraped (only the Memory panel via `process_resident_memory_bytes` renders).
- **Fix lead:** Talos etcd metrics need to be exposed (`cluster.etcd.extraArgs: listen-metrics-urls`) and a scrape config/ServiceMonitor pointing at the CP etcd `:2381`.

### Kubernetes / Scheduler — `2e6b6a3b4bddf1427b3a55aa1311c656`
17/18 panels dead. `up{job=kube-scheduler}` returns 3 series but **all value 0** — the scheduler scrape target is down. Zero `scheduler_*`/`process_*`/`rest_client_*` series exist under that job.
- **Fix lead:** kube-scheduler on Talos binds metrics to `127.0.0.1:10259`; the kube-prometheus-stack ServiceMonitor can't reach it. Compare with Controller-Manager (which *is* scraped — only its Goroutines panel is dead). Likely needs the scheduler bind-address patched or the SM endpoint corrected.

### Cilium Metrics — `vtuWtdumz`
70/70 panels dead. **cilium-agent** metrics are not scraped — only `cilium_operator_*` exist. The agent dashboard is completely blind.
- **Fix lead:** enable agent Prometheus metrics (`prometheus.enabled: true` on the Cilium agent) + ServiceMonitor. (Operator metrics already flow — see Cilium Operator below.)

### Home Assistant - Overview — `ha-overview`
5/11 panels dead: all power/energy panels. `W_value` and `kWh_value` absent in VictoriaMetrics.
- **Fix lead:** either no power/energy sensors are exporting to the HA Prometheus integration, or the metric suffix differs. Presence/light/switch/battery panels are healthy.

### Authelia Community Dashboard — `ddixu7wrrpuyod`
4/11 panels dead: `authelia_authn` and `authelia_authn_second_factor` absent (First/Second Factor, Authn requests panels). All `authelia_request*`/OIDC metrics present.
- **Fix lead:** likely a metric rename in the current Authelia version — update the dashboard queries.

### External DNS — `eea5u_I7z`
6/17 panels dead: per-record-type `external_dns_registry_a/aaaa_records`, `external_dns_source_a/aaaa_records`, `external_dns_controller_verified_a/aaaa_records` absent. Core endpoint/sync metrics present.
- **Fix lead:** this external-dns version doesn't emit the per-record-type gauges; dashboard predates the metric split.

### External Secrets Operator — `n4IdKaJVk`
1/24 dead: `externalsecret_sync_calls_error` absent (ExternalSecret sync call errors panel). Likely renamed to `externalsecret_sync_calls_total` in current ESO.

### Grafana Overview — `6be0s85Mk`
1/7 dead: `grafana_alerting_result_total` absent (Firing Alerts panel).

---

## P2 — Wrong-platform dashboards (expected dead — consider deleting or ignoring)

These were imported for hardware/cloud we don't run; the dead panels are inherent.
- **Node Exporter / AIX** (`7e0a61e486f727d763fb1d86fdd629c2`): 3/14 dead — AIX memory metric names; we run Linux node-exporter.
- **Node Exporter / MacOS** (`629701ea43bf69291922ea45f4a87d37`): 6/18 dead — macOS-only memory metrics on Linux nodes.
- **Cilium Operator** (`1GC0TT4Wz`): 7/9 dead — AWS EC2 ENI / cloud-IPAM metrics; not applicable on-prem. (process CPU/mem panels render.)

---

## P3 — Cosmetic / legacy-metric drift / disabled-by-design (low priority)

- **CoreDNS** (`vkQ0UHxik`): 1 dead (DO-bit) + 11 partial — legacy `*_count_total` metric names; panels render via `or` fallbacks to new-style metrics. Mostly cosmetic.
- **Node Exporter Full** (`rYdddlPWk`): 7 dead + 4 partial — `processes`, `systemd`, `tcpstat`, `interrupts` collectors disabled (typical Talos node-exporter). Expected.
- **K8s / Compute Resources** — `kube_resourcequota` (no ResourceQuotas defined) + `container_memory_swap` (Talos cgroup v2, no swap) absent:
  - Namespace (Pods) `85a562078cdf77779eaa1add43ccec1e`: 3 partial
  - Namespace (Workloads) `a87fb0d919ec0ea5f6543124e16c42a5`: 4 dead (quota scalar panels)
  - Node (Pods) `200ac8fdbfbb74b39aff88118e4d1c2c`: 1 partial (swap)
  - Pod `6581e46e4e5c7ba40a07646395ef7b23`: 1 dead (swap query)
- **K8s / Views / Global** (`k8s_views_global`): 1 dead (`container_cpu_cfs_throttled_seconds_total`) + 1 partial (some kube-state-metrics resource types missing).
- **K8s / Views / Namespaces** (`k8s_views_ns`): 1 dead (CFS throttle) + 1 partial (ingress/statefulset/daemonset/hpa/networkpolicy kube-state metrics).
- **K8s / Views / Pods** (`k8s_views_pods`): 2 dead — `container_oom_events_total`, `kube_pod_container_status_waiting_reason` absent.
- **K8s / API server** (`09ec8aa...`): 3 dead — `cluster_quantile:apiserver_request_sli_duration_seconds:histogram_quantile` recording rule + `go_goroutines`.
- **K8s / Kubelet** (`3138fa...`): 6 dead — config-error, runtime-op-duration buckets, `storage_operation_duration_seconds_count`, PLEG duration, `go_goroutines`.
- **K8s / Controller Manager** (`72e0e05...`): 1 dead — `go_goroutines`.
- **VictoriaLogs - single-node** (`OqPIZTX4z`): 11 dead — `go_*` runtime metrics + `vl_storage_per_query_*_bucket` histograms not scraped; 1 partial (`go_gc_cpu_seconds_total`).
- **Home Assistant - Sensors** (`ha-sensors`): 2 dead (`lx_value`, `V_value` — no such sensors) + Humidity panel empty via `friendly_name` label filter mismatch.
- **Envoy Clusters** (`8WkEOMnANKE6PW5hhpVv`): 1 dead — `envoy_cluster_outlier_detection_ejections_active`.
- **Envoy Gateway Global** (`bdn8lriao7myoa`): 4 dead — `watchable_panics_recovered_total`, `wasm_cache_lookup_total`, `wasm_remote_fetch_total` (wasm/watchable features unused).
- **CloudNativePG** (`cloudnative-pg`): 1 partial — Zone panel needs `kube_node_labels` (kube-state-metrics node-labels metric not scraped).

> **Recurring theme:** `go_goroutines` is absent **cluster-wide** (not just per-job), and shows up dead on API server, Controller Manager, Kubelet, Scheduler, and VictoriaLogs. This suggests a Prometheus `metric_relabel_configs` drop rule is stripping `go_*` runtime metrics. Worth a single check — fixing the relabel would revive several panels at once.

---

## Needs manual check (log-based — VictoriaLogs, not metric-testable)

- **Envoy Gateway - Access Logs** (`envoy-access-logs`): all 8 panels are VictoriaLogs LogsQL.
- **VictoriaLogs - Overview** (`victorialogs-overview`): all 4 panels log-based.

---

## Healthy — no dead/partial panels

Alertmanager / Overview · Cert-manager · Cloudflare Tunnels · Envoy Global ·
K8s Compute Resources (Multi-Cluster, Cluster, Workload) · K8s Networking (Cluster,
Namespace Pods, Namespace Workload, Pod, Workload) · K8s Persistent Volumes ·
K8s System (API Server, CoreDNS) · K8s Views (Nodes) · Node Exporter (Nodes, USE
Cluster, USE Node) · Prometheus Overview · Spegel.
