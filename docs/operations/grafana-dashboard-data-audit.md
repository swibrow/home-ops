# Grafana Dashboard Data Audit

Audit of all 54 Grafana dashboards on `pitower`, run 2026-06-03. Method: for every
panel, the underlying PromQL metric names were extracted and tested for existence in
the Prometheus / VictoriaMetrics datasources (`count(<metric>)` instant query). A panel
is **dead** when *all* its metrics are absent, **partial** when some are absent.
Log-based (VictoriaLogs) panels can't be metric-tested and are flagged for manual check.

Datasources: `prometheus` (default), `victoriametrics`, `victorialogs`.

Work through the priority buckets below. Healthy dashboards are listed at the bottom.

---

## Changes made — ✅ ALL APPLIED & VERIFIED (2026-06-03 → 2026-06-06)

1. `grafana/values.yaml` — node-exporter-full dashboard rev 37 → 45. ✅
2. `kube-prometheus-stack/values.yaml` — removed the `go_.*` drop from the default
   scrapeClass (restores Goroutines panels on API server / Controller-Manager /
   Kubelet / Scheduler / VictoriaLogs). ✅ `go_goroutines` back (76 series).
3. `kube-prometheus-stack/values.yaml` — **etcd scraped via
   `prometheusSpec.additionalScrapeConfigs`** (static job `kube-etcd` →
   `10.20.10.1/2/3:2381` http, `cluster=pitower` label). NOT `kubeEtcd.endpoints`:
   Talos etcd needs a selector-less manual Endpoints object, and ArgoCD's
   `resource.exclusions` drops `Endpoints`/`EndpointSlice` so it never applies
   (renders, "Synced", but absent). `kubeEtcd.enabled: true` kept for the dashboard;
   `service.enabled: false`. ✅ all 3 targets up, `etcd_server_has_leader`=3.
4. `controlplane.patch` — added `etcd.extraArgs.listen-metrics-urls`,
   `controllerManager.extraArgs.bind-address: 0.0.0.0`,
   `scheduler.extraArgs.bind-address: 0.0.0.0`. ✅ scheduler+CM `up=3`.

**Applying the Talos change** (item 4) — CPs are worker-01/02/03 = `10.20.10.1/2/3`:
```
cd kubernetes/talos/pitower
just config && just patch          # regenerate machine configs from the patch
just apply-controlplanes           # applies worker-0{1,2,3}.yaml to .1/.2/.3
```
`apply-config` rolls the **scheduler/CM static pods** (kubelet picks up the manifest
change) but does NOT cycle the Talos-managed **etcd** service. etcd `extraArgs`
(listen-metrics-urls) only take effect on a **node reboot** — `service etcd restart`
is unsupported by the Talos API. So after apply, roll the CPs one at a time:
`talosctl reboot -n 10.20.10.{2,3,1} --wait` (followers first, leader last; quorum
stays 2/3). Items 1–3 ship via ArgoCD on git push.

**Still pending live check**: ~~Ceph mgr ServiceMonitor~~ (resolved 2026-06-05),
~~Cilium-agent ServiceMonitor~~ (resolved 2026-06-06 — `serviceMonitor.enabled: true`;
6/6 agent targets up, 212 `cilium_*` families flowing). **All P1 items resolved.**

---

## Root-cause analysis (2026-06-03)

Verified via Prometheus (`up` by job) + repo config. Live `kubectl` diagnosis was
blocked — the API VIP `10.20.10.0:6443` was unreachable from the workstation (needs
home network/VPN). Items marked **[needs live check]** await on-network inspection.

| Symptom | Root cause | Determinable fix |
|---|---|---|
| `go_*` absent cluster-wide (Goroutines dead on 5 dashboards) | **✅ RESOLVED (2026-06-05).** Intentional `scrapeClasses[default].metricRelabelings` drop of `go_.*`. | Removed the drop; `go_goroutines` back (76 series). |
| etcd 15/16 dead — no `etcd` job exists | **✅ RESOLVED (2026-06-06).** Talos etcd metrics weren't exposed AND the chart's `kubeEtcd.endpoints` Endpoints object is dropped by ArgoCD `resource.exclusions`. | `controlplane.patch` `etcd.extraArgs.listen-metrics-urls: http://0.0.0.0:2381` + **node reboot** per CP (etcd service can't be restarted via API) + scrape via `additionalScrapeConfigs` static job. All 3 `kube-etcd` targets up. |
| Scheduler 17/18 + Controller-Manager (audit false-positive) — `up==0` for all 3 each | **✅ RESOLVED (2026-06-06).** Components bind metrics to `127.0.0.1`. | `scheduler`/`controllerManager` `extraArgs.bind-address: 0.0.0.0` in `controlplane.patch` + `apply-config` (static pods roll, no reboot needed). Both `up=3`. |
| Ceph 64 panels dead — no `ceph`/`rook` job | **✅ RESOLVED (2026-06-05).** Operator chart `monitoring.enabled: false` vs cluster chart `true` → operator SA forbidden from creating ServiceMonitors. | Set operator `monitoring.enabled: true` (commit `939a8ce1`) + one operator reconcile. Both SMs now up, all `ceph_*` metrics flowing. |
| Cilium Metrics 70/70 dead — only `cilium-operator` job (no agent) | **✅ RESOLVED (2026-06-06).** Live agent values (`apps/pitower/kube-system/cilium/operator/values.yaml`) had `prometheus.enabled: true` but `prometheus.serviceMonitor.enabled: false` — agent served 1580 `cilium_*` on `:9962` but no `cilium-agent` SM existed. | Set `prometheus.serviceMonitor.enabled: true` — chart adds the `metrics`/9962 port to the cilium-agent Service and creates the SM. |

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

### etcd — `c2f4e12cdf69feb95caa41a5a1b423d9` — ✅ RESOLVED (2026-06-06)
~~15/16 panels dead. No `etcd_*` or `grpc_server_*` metrics scraped.~~
- **Root cause (two-part):** (1) Talos etcd served metrics only on the cert-guarded client
  port — no `:2381` listener; (2) the chart's `kubeEtcd.endpoints` needs a selector-less
  manual Endpoints object, which ArgoCD's `resource.exclusions` (Endpoints/EndpointSlice)
  silently drops.
- **Fix:** `controlplane.patch` `etcd.extraArgs.listen-metrics-urls: http://0.0.0.0:2381`;
  scrape via `prometheusSpec.additionalScrapeConfigs` (static `kube-etcd` job →
  `10.20.10.1/2/3:2381`, `cluster=pitower`) instead of `kubeEtcd.endpoints`. etcd `extraArgs`
  need a **node reboot** to take effect (`service etcd restart` unsupported); rolled CPs one
  at a time.
- **Verified:** all 3 `kube-etcd` targets `up=1`, `etcd_server_has_leader`=3, gRPC/mvcc/disk metrics flowing.

### Kubernetes / Scheduler — `2e6b6a3b4bddf1427b3a55aa1311c656` — ✅ RESOLVED (2026-06-06)
~~17/18 panels dead. `up{job=kube-scheduler}` returns 3 series but all value 0.~~
- **Root cause:** kube-scheduler + controller-manager bound metrics to `127.0.0.1`.
- **Fix:** `scheduler`/`controllerManager` `extraArgs.bind-address: 0.0.0.0` in `controlplane.patch`
  + `apply-config` (static pods roll on manifest change — no reboot needed, unlike etcd).
- **Verified:** scheduler + controller-manager both `up=3`.

### Cilium Metrics — `vtuWtdumz` — ✅ RESOLVED (2026-06-06)
~~70/70 panels dead. cilium-agent metrics are not scraped — only `cilium_operator_*` exist.~~
- **Root cause:** live agent values had `prometheus.enabled: true` (agent served 1580 `cilium_*`
  on `:9962`) but `prometheus.serviceMonitor.enabled: false` — so no `cilium-agent` ServiceMonitor
  was ever created (only `cilium-operator`).
- **Fix:** `prometheus.serviceMonitor.enabled: true` in
  `apps/pitower/kube-system/cilium/operator/values.yaml` — the chart adds the `metrics`/9962 port
  to the cilium-agent Service and creates the `cilium-agent` SM.

### Home Assistant - Overview — `ha-overview` — ✅ mostly RESOLVED (2026-06-06)
~~5/11 panels dead: all power/energy panels. `W_value` and `kWh_value` absent in VictoriaMetrics.~~
- **Re-verified:** `W_value`, `kWh_value`, `state_state` all present and emitting now — the power/energy and domain panels render. Original audit reading was stale.
- **Remaining:** 1 panel ("Battery levels", `%_value{friendly_name=~".*battery.*"}`) is empty — **no `%`-unit sensors reach VictoriaMetrics at all** (no humidity/battery percent series export). This is an HA Prometheus-integration export gap, not a dashboard query bug; left as-is (no sensible substitute metric for a battery panel).

### Authelia Community Dashboard — `ddixu7wrrpuyod`
4/11 panels dead: `authelia_authn`, `authelia_authn_second_factor`, `authelia_authz` absent (First/Second Factor, Authn/Authz requests panels). All `authelia_request*`/OIDC metrics present.
- **Resolution (2026-06-06): WONTFIX — Authelia is being decommissioned** (IdP consolidation onto Kanidm). Not a clean rename: our Authelia build only exports `authelia_request*` + an `authelia_authn_duration` histogram (event-only, currently no data), with no counter equivalent for the dead panels. Dashboard will be removed with Authelia; no query work warranted.

### External DNS — `eea5u_I7z` — ✅ RESOLVED (2026-06-06)
~~6/17 panels dead: per-record-type `external_dns_registry_a/aaaa_records`, `external_dns_source_a/aaaa_records`, `external_dns_controller_verified_a/aaaa_records` absent.~~
- **Root cause:** current external-dns collapsed the per-record-type metric names into a single `external_dns_*_records` series carrying a `record_type` label (`a`/`aaaa`/`cname`/`txt`). gnetId 15038 rev3 predates that split.
- **Fix:** vendored the dashboard to `grafana/dashboards/external-dns.json` (configMapGenerator `grafana-dashboards-networking`, folder Networking) and rewrote the 6 panels to `external_dns_<scope>_records{record_type="a"|"aaaa", …}`. Removed the gnetId import from `grafana/values.yaml`. (`record_type="aaaa"` reads 0 until an IPv6 record exists — expected.)

### External Secrets Operator — `n4IdKaJVk`
~~1/24 dead: `externalsecret_sync_calls_error` absent (ExternalSecret sync call errors panel). Likely renamed to `externalsecret_sync_calls_total` in current ESO.~~
- **Resolution (2026-06-06): RESOLVED — no action.** Re-verified against Prometheus: `externalsecret_sync_calls_error` **is** present and emitting (alongside `_total`), and all 24 panels return data. Dashboard is sourced from the ESO repo's `main` branch (`grafana/values.yaml`), so it self-heals to upstream — the original audit reading was stale.

### Grafana Overview — `6be0s85Mk`
1/7 dead: `grafana_alerting_result_total` absent (Firing Alerts panel).
- **Status (2026-06-06): known fix, WONTFIX via chart.** Modern replacement is `grafana_alerting_alerts{state="alerting"}` (verified present). But this dashboard ships from the **kube-prometheus-stack** chart (`templates/grafana/dashboards-1.14/grafana-overview.yaml`, vendored), so a query edit there is clobbered on the next chart bump — same situation as CoreDNS. Not worth a chart-dashboard override for one stat panel; revisit only if kube-prometheus-stack fixes it upstream or the panel becomes load-bearing.

---

## P2 — Wrong-platform dashboards (expected dead — consider deleting or ignoring)

These were imported for hardware/cloud we don't run; the dead panels are inherent.
- **Node Exporter / AIX** (`7e0a61e486f727d763fb1d86fdd629c2`): 3/14 dead — AIX memory metric names; we run Linux node-exporter.
- **Node Exporter / MacOS** (`629701ea43bf69291922ea45f4a87d37`): 6/18 dead — macOS-only memory metrics on Linux nodes.
- **Cilium Operator** (`1GC0TT4Wz`): 7/9 dead — AWS EC2 ENI / cloud-IPAM metrics; not applicable on-prem. (process CPU/mem panels render.)

---

## P3 — Cosmetic / legacy-metric drift / disabled-by-design (low priority)

- **CoreDNS** (`vkQ0UHxik`): **WONTFIX (verified 2026-06-06).** All rate/size/duration/rcode/qtype panels already render — each query carries an `or` fallback to the modern metric (`coredns_dns_requests_total{type}`, `coredns_dns_responses_total{rcode}`, `*_seconds_bucket`), all of which emit. The only truly-dead series is the **DO-bit** panel (`coredns_dns_request_do_count_total`/`coredns_dns_do_requests_total`) — our CoreDNS build exports no DO-bit metric, so there is no query fix (would require enabling it in CoreDNS config). Dashboard is owned by the `kube-prometheus-stack` chart (vendored template), so editing it would be clobbered on the next chart bump. No change made.
- **Node Exporter Full** (`rYdddlPWk`): 7 dead + 4 partial — `processes`, `systemd`, `tcpstat`, `interrupts` collectors disabled (typical Talos node-exporter). Expected.
- **K8s / Compute Resources** — `kube_resourcequota` (no ResourceQuotas defined) + `container_memory_swap` (Talos cgroup v2, no swap) absent:
  - Namespace (Pods) `85a562078cdf77779eaa1add43ccec1e`: 3 partial
  - Namespace (Workloads) `a87fb0d919ec0ea5f6543124e16c42a5`: 4 dead (quota scalar panels)
  - Node (Pods) `200ac8fdbfbb74b39aff88118e4d1c2c`: 1 partial (swap)
  - Pod `6581e46e4e5c7ba40a07646395ef7b23`: 1 dead (swap query)
- **K8s / Views / Global** (`k8s_views_global`): 1 dead (`container_cpu_cfs_throttled_seconds_total`) + 1 partial. **CFS-throttle panel is unfixable here (2026-06-06):** Talos cadvisor on cgroup v2 exports only `container_cpu_cfs_throttled_periods_total` (+ `_periods_total`), never the `_seconds_total` counter the panel needs. dotdc dashboards are pulled from `master` (self-updating) — vendoring all three just to swap one panel to a periods ratio isn't worth losing upstream updates. WONTFIX unless dotdc adds a periods fallback.
- **K8s / Views / Namespaces** (`k8s_views_ns`): 1 dead (same CFS-throttle Talos limitation as Global) + 1 partial (ingress/statefulset/daemonset/hpa/networkpolicy kube-state metrics).
- **K8s / Views / Pods** (`k8s_views_pods`): **NOT dead (2026-06-06).** Re-verified: `container_oom_events_total` (660) and `kube_pod_container_status_waiting_reason` (2) both present and emitting — the audit caught them at a moment with zero OOMs / no waiting containers (empty ≠ broken). No action.
- **K8s / API server** (`09ec8aa...`): ✅ **whole-dashboard "no data" FIXED (2026-06-06, commit c46f98d5).** Root cause was NOT missing metrics — the hidden `cluster` var (`label_values(up{job="apiserver"}, cluster)`) resolved empty because `cluster` was stamped via `metricRelabelings` (which can't label the synthetic `up`), so every `cluster="$cluster"` panel matched nothing. Fixed by adding a conditional target relabeling to the default scrapeClass (`up` now carries `cluster=pitower` cluster-wide; rook keeps `rook-ceph`). See [reference] memory `cluster label on up`. **Same fix revives CoreDNS + the k8s-views dashboards** (same empty-`cluster`-var cause). **Still dead:** top Availability/error panels — the `apiserver_request:availability30d` / `code_resource:apiserver_request_total:rate5m` / `cluster_quantile:...sli_duration...` recording rules carry no `cluster` label, so they stay empty even with the var fixed (separate kube-prometheus-stack rule issue); plus `go_goroutines`.
- **K8s / Kubelet** (`3138fa...`): 6 dead — config-error, runtime-op-duration buckets, `storage_operation_duration_seconds_count`, PLEG duration, `go_goroutines`.
- **K8s / Controller Manager** (`72e0e05...`): 1 dead — `go_goroutines`.
- **VictoriaLogs - single-node** (`OqPIZTX4z`): 11 dead — `go_*` runtime metrics + `vl_storage_per_query_*_bucket` histograms not scraped; 1 partial (`go_gc_cpu_seconds_total`).
- **Home Assistant - Sensors** (`ha-sensors`): ✅ **RESOLVED (2026-06-06).** Only `°C_value` (temp) of the original panels had data; `%_value`/`lx_value`/`V_value` (humidity/lux/voltage) aren't collected at all, but `W_value`/`kWh_value`/`A_value` (power/energy/current) are. Repurposed the three dead panels in the local `grafana/dashboards/home-assistant-sensors.json` → Power (W)/Energy (kWh)/Current (A) so the board reflects the sensors that actually exist; temperature + all-sensors table unchanged.
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
