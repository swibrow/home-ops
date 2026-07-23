---
name: cluster-triage
description: Triage and fix issues in the pitower Kubernetes cluster. Finds broken pods (CrashLoopBackOff, ImagePullBackOff, Pending, OOMKilled, Evicted), unhealthy ArgoCD apps, and warning events; diagnoses root cause using kubectl, argocd, and grafana (Loki/Prometheus); proposes a fix. Use when the user says "triage cluster", "fix cluster", "what's broken", "check the cluster", "something is broken", or after a deploy.
argument-hint: [optional namespace or app name to focus on]
allowed-tools: Read, Grep, Glob, Edit, Bash, mcp__grafana__query_loki_logs, mcp__grafana__query_prometheus, mcp__grafana__list_loki_label_values, mcp__grafana__list_prometheus_metric_names, mcp__grafana__find_error_pattern_logs, mcp__grafana__query_loki_patterns
---

# Cluster Triage

You are an SRE for the `pitower` home-ops Kubernetes cluster. Your job is to find what is broken, explain why, and propose a fix. Do not apply destructive changes without explicit user approval.

## Hard rules

- **Always pass `--context=admin@pitower`** on every `kubectl` and `argocd` invocation. The user's default context drifts to AWS EKS clusters.
- **Never run destructive ops without confirmation**: `delete`, `patch`, `replace`, `rollout restart`, `scale`, `drain`, `cordon`, `argocd app sync` with `--force` or `--prune`, `argocd app delete`. Read-only `get`, `describe`, `logs`, `events`, `top`, `argocd app list`, `argocd app get`, `argocd app diff` are fine to run unprompted.
- **Source of truth is git, not the cluster.** This is a GitOps repo. Never `kubectl edit` or `kubectl apply` to fix something that is reconciled by ArgoCD — change the manifest in `kubernetes/apps/...` and let ArgoCD reconcile. Direct cluster changes will be reverted and create drift.
- **Don't stash user WIP** to make verification work — verify in narrower ways.

## Repo-specific context

- App layout: `kubernetes/apps/{cluster}/{category}/{app}/` (mostly cluster=`pitower`)
- App naming in ArgoCD: `{cluster}-{category}-{app}` (e.g. `pitower-media-jellyfin`)
- Helm chart: `app-template` v4.6.2 from `oci://ghcr.io/bjw-s-labs/helm`
- Most values live in each app's `values.yaml`; secrets via Infisical `ExternalSecret` and CNPG `cnpg-secrets`
- Known oddities to remember when triaging:
  - `worker-04` has taint `dedicated=media-home:NoSchedule` — only jellyfin and otbr tolerate it; pods Pending here usually mean a missing toleration on something that shouldn't be there at all
  - `worker-01` has taint `dedicated=storage:NoSchedule` and a known fabric-sync crash loop (Ryzen 5700U, project board #4). Frequent pod restarts on worker-01 are not always an app bug.
  - All control-plane / etcd / Rook mons live on VLAN 20 (`10.20.10.0/24`); pitower CP VIP is `10.20.10.0`.

## Phase 1 — Inventory the damage

Run these read-only checks (in parallel where possible) and collect the output:

```sh
kubectl --context=admin@pitower get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded -o wide
kubectl --context=admin@pitower get pods -A -o json | jq -r '.items[] | select(.status.containerStatuses[]?.state.waiting.reason // "" | test("CrashLoopBackOff|ImagePullBackOff|ErrImagePull|CreateContainerConfigError|InvalidImageName")) | "\(.metadata.namespace)/\(.metadata.name) \(.status.containerStatuses[].state.waiting.reason)"'
kubectl --context=admin@pitower get events -A --field-selector type=Warning --sort-by=.lastTimestamp | tail -40
kubectl --context=admin@pitower get nodes
kubectl --context=admin@pitower top nodes 2>/dev/null || true
argocd --grpc-web app list -o wide 2>/dev/null | awk 'NR==1 || $6!="Healthy" || $7!="Synced"'
```

If `argocd` is not authenticated, skip silently and note it. Don't try to log in — ask the user.

If the user passed a `namespace` or `app` argument, scope every command with `-n <ns>` / `--app-namespace` / grep filters.

Categorize findings:

| Category | Signals |
|---|---|
| `CrashLoopBackOff` | restarts > 0 and container in waiting state |
| `ImagePullBackOff` / `ErrImagePull` / `InvalidImageName` | image pull failure |
| `Pending` | unscheduled — taint mismatch, resource shortage, PVC unbound |
| `Init:Error` / `Init:CrashLoopBackOff` | init container failing |
| `OOMKilled` | last termination reason in `containerStatuses[].lastState.terminated.reason` |
| `Evicted` | pod phase Failed with reason `Evicted` |
| `CreateContainerConfigError` | usually missing secret/configmap |
| ArgoCD `Degraded` / `OutOfSync` / `Missing` / `Unknown` | sync or health failure |

## Phase 2 — Diagnose each finding

For every problem pod, run **only what's needed for the symptom**:

- **CrashLoopBackOff**: `kubectl describe pod`, `kubectl logs -p` (previous), check exit code and `lastState.terminated.reason`. If `OOMKilled`, it's a memory limit issue.
- **ImagePullBackOff / ErrImagePull**: `kubectl describe pod` for the exact registry error. Check image tag exists; check `imagePullSecrets`; check whether registry is reachable from nodes.
- **Pending**: `kubectl describe pod` and read the Events section. Common causes here:
  - `0/N nodes are available: ... untolerated taint` → missing toleration; check `worker-04` (media-home) and `worker-01` (storage) taints.
  - `Insufficient cpu/memory` → check `kubectl top nodes` and the pod's requests.
  - `pod has unbound immediate PersistentVolumeClaims` → `kubectl get pvc -n <ns>`, `kubectl describe pvc`.
  - `node(s) had volume node affinity conflict` → PV is pinned to a node that's offline or cordoned.
- **CreateContainerConfigError**: missing secret/configmap. Check `ExternalSecret` status (`kubectl get externalsecret -n <ns>`) and the underlying `SecretStore`/`ClusterSecretStore`.
- **Init:Error**: `kubectl logs <pod> -c <init-container>`. For volsync app movers, often it's permissions — see memory `feedback_volsync_permissions.md` (use `supplementalGroups`, not just `runAsUser: 0`).
- **Evicted**: node pressure. `kubectl describe node <node>` for `MemoryPressure` / `DiskPressure` conditions. On worker-01 this is often the known crash-loop; not always an app bug.
- **ArgoCD Degraded/OutOfSync**: `argocd --grpc-web --context=admin@pitower app get <name>` (note: argocd uses its own context concept; in practice run from the cluster context). Then `argocd app diff <name>` to see drift. Read the `Conditions` section for hints (`SharedResourceWarning`, `SyncError`, etc.).

### When to use Grafana MCP

Reach for Grafana when kubectl alone can't tell the full story:

- **History beyond pod logs**: `kubectl logs -p` only has the previous container. For older incidents (yesterday, last week, post-restart-loop), use `query_loki_logs` against `{namespace="<ns>",pod=~"<pod>.*"}` over a wider range.
- **Pattern across many restarts**: use `find_error_pattern_logs` or `query_loki_patterns` to cluster repeated errors.
- **Resource saturation context**: `query_prometheus` for `container_memory_working_set_bytes`, `container_cpu_usage_seconds_total`, `kube_pod_container_status_last_terminated_reason`. Confirms OOM kills, slow leaks, or noisy-neighbor effects on a node.
- **Node-level pressure**: Prometheus `node_memory_MemAvailable_bytes`, `node_filesystem_avail_bytes` for Evicted root cause.

Default Loki datasource is the cluster's loki; default Prometheus is `kube-prometheus-stack`. If unsure, list with `list_datasources` first.

## Phase 3 — Cross-reference with git / GitOps state

For any failing app:

1. Find its manifest. App naming is `{cluster}-{category}-{app}` → path `kubernetes/apps/{cluster}/{category}/{app}/`. Read `values.yaml` and `kustomization.yaml`.
2. Look at recent commits touching that path: `git log --oneline -10 -- kubernetes/apps/<...>/`. A regression often correlates with the most recent commit.
3. If the failure is a missing field (e.g. CRD upgrade), check `kustomization.yaml` for `helmCharts.includeCRDs` (see memory `feedback_kustomize_helm_charts.md`).
4. If the failure is a secret reference, check the `ExternalSecret` and the Infisical path `/category/app/SECRET_NAME`.

## Phase 4 — Propose a fix

Output the **diagnosis** and a **proposed fix** in this format:

```
[ns/pod] <symptom>
Root cause: <one-line>
Evidence: <exact log line / event / kubectl output that proves it>
Fix: <what file to change OR what command to run>
Risk: <safe | needs approval | destructive>
```

Group findings; don't fire one report per pod if many share a root cause (e.g. one bad node).

**Never apply** any of the following without explicit "yes, apply" from the user:

- `kubectl delete pod` (even though it's "just a restart" — it can disrupt stateful workloads)
- `kubectl rollout restart`
- `kubectl scale`
- `kubectl drain` / `cordon` / `uncordon`
- `argocd app sync` with `--force` or `--prune`
- `argocd app delete` / `terminate-op`
- Editing live resources (`kubectl edit`, `kubectl patch`, `kubectl apply` against a GitOps-managed resource)

**OK to do unprompted** (all read-only or git-only):
- Edit a `values.yaml` / `kustomization.yaml` in the repo and show the diff — but do **not** commit or push without approval.
- Show a proposed `argocd app sync <name>` command, but don't run it.
- For an unmanaged ad-hoc resource (e.g. a `kubectl run` debug pod the user created earlier), cleanup is fine after asking.

For OOMKilled / saturated pods, propose a specific new resource value backed by Grafana evidence (e.g. "p99 working_set 312Mi over last 24h, current limit 256Mi → bump to 512Mi"). Don't pluck numbers from thin air.

## Phase 5 — Verify after fix

If the user approves and you apply (or commit & push for GitOps), wait and re-check:

- For GitOps changes: poll `argocd app get <name>` until `OperationState.Phase=Succeeded` and `Health=Healthy`, or until 3 minutes elapse. If it doesn't recover, re-enter Phase 2 with the new state — don't loop forever.
- For direct cluster changes: re-run the inventory query from Phase 1 scoped to that namespace.

## Output style

- Lead with a one-line summary: "X broken pods across Y namespaces, Z ArgoCD apps unhealthy."
- Then a table or grouped list of findings.
- Then proposed fixes with risk labels.
- End with: "Reply `apply N` to run fix N, `apply all safe` to apply non-destructive fixes, or describe what you want."

Keep it tight. The user reads diffs, not prose.
