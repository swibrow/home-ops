#!/usr/bin/env python3
"""Surface workloads where requests are far above actual usage.

Reads `kubectl top pods -A` (live snapshot) and `kubectl get pods -A -o json`
(declared requests), ranks the biggest memory and CPU gaps, and emits a
markdown report to stdout. Intended to run on a schedule and post the result
to a rolling GitHub issue.

Limitation: this is a single-point-in-time sample. Bursty workloads
(transcoders, indexers, cron-driven sync jobs) may show low usage in the
snapshot and look wasteful when they aren't. Treat this as a triage list,
not a directive.
"""

from __future__ import annotations

import json
import subprocess
import sys
from collections import defaultdict
from datetime import datetime, timezone

CPU_REQ_FLOOR_M = 200
CPU_WASTE_FLOOR_M = 200
MEM_REQ_FLOOR_MI = 200
MEM_WASTE_FLOOR_MI = 300
TOP_N = 25


def parse_cpu(v) -> float:
    """Return millicpu."""
    if v in (None, "", "0", 0):
        return 0.0
    s = str(v)
    if s.endswith("m"):
        return float(s[:-1])
    if s.endswith("n"):
        return float(s[:-1]) / 1_000_000
    if s.endswith("u"):
        return float(s[:-1]) / 1_000
    return float(s) * 1000


def parse_mem(v) -> float:
    """Return MiB."""
    if v in (None, "", "0", 0):
        return 0.0
    s = str(v)
    units = {
        "Ki": 1 / 1024,
        "Mi": 1.0,
        "Gi": 1024.0,
        "Ti": 1024.0 * 1024,
        "K": 1000 / (1024 * 1024),
        "M": 1000 * 1000 / (1024 * 1024),
        "G": 1_000_000_000 / (1024 * 1024),
    }
    for u, mult in units.items():
        if s.endswith(u):
            return float(s[: -len(u)]) * mult
    return float(s) / (1024 * 1024)


def fmt_cpu_m(m: float) -> str:
    return f"{m:.0f}m"


def fmt_mem_mi(mi: float) -> str:
    if mi >= 1024:
        return f"{mi / 1024:.1f}Gi"
    return f"{mi:.0f}Mi"


def workload_key(pod: dict) -> tuple[str, str]:
    """Group replicas of the same deployment/sts/ds together."""
    ns = pod["metadata"]["namespace"]
    pod_name = pod["metadata"]["name"]
    owners = pod["metadata"].get("ownerReferences", [])
    if owners:
        kind = owners[0]["kind"]
        name = owners[0]["name"]
        if kind == "ReplicaSet":
            # strip the trailing -<hash> to recover the Deployment name
            name = name.rsplit("-", 1)[0]
        elif kind == "Node":
            # static pods are owned by the Node they run on — keep the pod
            # name with the trailing -<nodename> stripped so siblings group
            return ns, pod_name.rsplit("-", 1)[0]
        return ns, name
    return ns, pod_name


def main() -> int:
    top = subprocess.run(
        ["kubectl", "top", "pods", "-A", "--no-headers"],
        capture_output=True,
        text=True,
        check=True,
    )
    pods = subprocess.run(
        ["kubectl", "get", "pods", "-A", "-o", "json"],
        capture_output=True,
        text=True,
        check=True,
    )

    usage: dict[tuple[str, str], tuple[float, float]] = {}
    for line in top.stdout.splitlines():
        parts = line.split()
        if len(parts) < 4:
            continue
        ns, name, cpu, mem = parts[:4]
        usage[(ns, name)] = (parse_cpu(cpu), parse_mem(mem))

    workloads: dict[tuple[str, str], dict[str, float]] = defaultdict(
        lambda: {
            "cpu_req": 0.0,
            "cpu_use": 0.0,
            "mem_req": 0.0,
            "mem_use": 0.0,
            "replicas": 0,
        }
    )

    for pod in json.loads(pods.stdout)["items"]:
        if pod.get("status", {}).get("phase") != "Running":
            continue
        ns = pod["metadata"]["namespace"]
        name = pod["metadata"]["name"]
        cpu_use, mem_use = usage.get((ns, name), (None, None))
        if cpu_use is None:
            continue  # metrics-server may have stale or missing data

        cpu_req = mem_req = 0.0
        for c in pod["spec"].get("containers", []):
            r = c.get("resources", {}).get("requests", {})
            cpu_req += parse_cpu(r.get("cpu"))
            mem_req += parse_mem(r.get("memory"))

        key = workload_key(pod)
        w = workloads[key]
        w["cpu_req"] += cpu_req
        w["cpu_use"] += cpu_use
        w["mem_req"] += mem_req
        w["mem_use"] += mem_use
        w["replicas"] += 1

    rows = []
    for (ns, name), w in workloads.items():
        rows.append(
            {
                "ns": ns,
                "name": name,
                "replicas": int(w["replicas"]),
                "cpu_req": w["cpu_req"],
                "cpu_use": w["cpu_use"],
                "mem_req": w["mem_req"],
                "mem_use": w["mem_use"],
            }
        )

    mem_offenders = sorted(
        [
            r
            for r in rows
            if r["mem_req"] >= MEM_REQ_FLOOR_MI
            and (r["mem_req"] - r["mem_use"]) >= MEM_WASTE_FLOOR_MI
        ],
        key=lambda r: -(r["mem_req"] - r["mem_use"]),
    )[:TOP_N]

    cpu_offenders = sorted(
        [
            r
            for r in rows
            if r["cpu_req"] >= CPU_REQ_FLOOR_M
            and (r["cpu_req"] - r["cpu_use"]) >= CPU_WASTE_FLOOR_M
        ],
        key=lambda r: -(r["cpu_req"] - r["cpu_use"]),
    )[:TOP_N]

    total_cpu_req = sum(r["cpu_req"] for r in rows)
    total_cpu_use = sum(r["cpu_use"] for r in rows)
    total_mem_req = sum(r["mem_req"] for r in rows)
    total_mem_use = sum(r["mem_use"] for r in rows)

    out = []
    ts = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
    out.append(f"_Snapshot taken {ts}_")
    out.append("")
    out.append("## Cluster totals")
    out.append("")
    out.append("| Resource | Requested | In use | Utilization |")
    out.append("|---|---:|---:|---:|")
    out.append(
        f"| CPU | {total_cpu_req / 1000:.1f} cores | {total_cpu_use / 1000:.2f} cores "
        f"| {(total_cpu_use / total_cpu_req * 100) if total_cpu_req else 0:.0f}% |"
    )
    out.append(
        f"| Memory | {total_mem_req / 1024:.1f} Gi | {total_mem_use / 1024:.1f} Gi "
        f"| {(total_mem_use / total_mem_req * 100) if total_mem_req else 0:.0f}% |"
    )
    out.append("")
    out.append("## Memory: top over-requesters")
    out.append("")
    if mem_offenders:
        out.append("| Namespace | Workload | Replicas | Requested | Used | Waste | Utilization |")
        out.append("|---|---|---:|---:|---:|---:|---:|")
        for r in mem_offenders:
            waste = r["mem_req"] - r["mem_use"]
            ratio = r["mem_use"] / r["mem_req"] if r["mem_req"] else 0
            out.append(
                f"| `{r['ns']}` | `{r['name']}` | {r['replicas']} "
                f"| {fmt_mem_mi(r['mem_req'])} | {fmt_mem_mi(r['mem_use'])} "
                f"| **{fmt_mem_mi(waste)}** | {ratio * 100:.0f}% |"
            )
    else:
        out.append("_No workloads exceed thresholds._")
    out.append("")
    out.append("## CPU: top over-requesters")
    out.append("")
    if cpu_offenders:
        out.append("| Namespace | Workload | Replicas | Requested | Used | Waste | Utilization |")
        out.append("|---|---|---:|---:|---:|---:|---:|")
        for r in cpu_offenders:
            waste = r["cpu_req"] - r["cpu_use"]
            ratio = r["cpu_use"] / r["cpu_req"] if r["cpu_req"] else 0
            out.append(
                f"| `{r['ns']}` | `{r['name']}` | {r['replicas']} "
                f"| {fmt_cpu_m(r['cpu_req'])} | {fmt_cpu_m(r['cpu_use'])} "
                f"| **{fmt_cpu_m(waste)}** | {ratio * 100:.0f}% |"
            )
    else:
        out.append("_No workloads exceed thresholds._")
    out.append("")
    out.append("## Notes")
    out.append("")
    out.append(
        f"- Thresholds: memory ≥ {MEM_REQ_FLOOR_MI}Mi req and ≥ {MEM_WASTE_FLOOR_MI}Mi waste; "
        f"CPU ≥ {CPU_REQ_FLOOR_M}m req and ≥ {CPU_WASTE_FLOOR_M}m waste."
    )
    out.append(
        "- Replicas are summed: a 2-replica deployment with 1Gi each shows 2Gi requested."
    )
    out.append(
        "- Single-point-in-time snapshot — bursty workloads (transcoders, indexers) "
        "can look wasteful when they aren't. Cross-check Grafana before lowering."
    )
    out.append(
        "- Complements `krr-rightsize.yaml`, which auto-PRs only against bjw-s "
        "app-template charts. Use this list to catch the rest (rook-ceph, envoy, "
        "argocd, helm-managed charts, etc.)."
    )

    print("\n".join(out))
    return 0


if __name__ == "__main__":
    sys.exit(main())
