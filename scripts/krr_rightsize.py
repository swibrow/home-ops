#!/usr/bin/env python3
"""Apply KRR recommendations to resource requests across the repo.

Two complementary mechanisms feed the same patching logic:

1. **app-template auto-discovery** — for bjw-s-labs/app-template charts the
   structure is uniform, so the script locates the values.yaml under
   kubernetes/apps/pitower/<namespace>/<app>/ and updates
   controllers.<ctrl>.containers.<container>.resources.requests.{cpu,memory}.

2. **inline marker comments** — for every other chart/CR schema (rook, envoy,
   victoria-metrics, dragonfly, toolhive, crowdsec, ...) the KRR→block mapping
   can't be inferred, so it is declared explicitly. Annotate any `resources:`
   block with a comment on (or directly above) the `resources:` line:

       # krr: <workload-name>/<container>[@<namespace>]
       resources:
         requests:
           cpu: 100m
           memory: 512Mi

   <workload-name>/<container> must match KRR's reported object name + container
   (i.e. `kubectl`'s deployment/statefulset/daemonset name). Namespace defaults
   to the sibling kustomization.yaml's `namespace:` (or the category dir); use
   `@<namespace>` to override. The marked block's requests are patched in place,
   regardless of how the surrounding chart nests it. Multi-document files are
   supported.

Skips any delta below the configured thresholds. A workload with neither an
app-template match nor a marker is left untouched (and reported on stderr).
"""

from __future__ import annotations

import argparse
import json
import math
import re
import sys
import urllib.parse
import urllib.request
from dataclasses import dataclass
from pathlib import Path

from ruamel.yaml import YAML

REPO_ROOT = Path(__file__).resolve().parent.parent
APPS_ROOT = REPO_ROOT / "kubernetes" / "apps" / "pitower"
APP_TEMPLATE_CHART = "app-template"


@dataclass
class Change:
    path: Path
    namespace: str
    controller: str
    container: str
    field: str
    before: str
    after: str


def load_yaml(path: Path):
    yaml = YAML()
    yaml.preserve_quotes = True
    yaml.width = 4096
    yaml.indent(mapping=2, sequence=4, offset=2)
    return yaml, yaml.load(path.read_text())


def fmt_cpu(cores: float) -> str:
    millicpu = max(10, math.ceil(cores * 1000))
    return f"{millicpu}m"


def fmt_mem(bytes_: float) -> str:
    mib = math.ceil(bytes_ / (1024 * 1024))
    if mib >= 1024 and mib % 1024 == 0:
        return f"{mib // 1024}Gi"
    return f"{mib}Mi"


def parse_cpu(value) -> float | None:
    if value is None:
        return None
    s = str(value).strip()
    if s.endswith("m"):
        return float(s[:-1]) / 1000
    try:
        return float(s)
    except ValueError:
        return None


def parse_mem(value) -> float | None:
    if value is None:
        return None
    s = str(value).strip()
    units = {
        "Ki": 1024,
        "Mi": 1024**2,
        "Gi": 1024**3,
        "Ti": 1024**4,
        "K": 1000,
        "M": 1000**2,
        "G": 1000**3,
        "T": 1000**4,
    }
    for suffix, mult in units.items():
        if s.endswith(suffix):
            try:
                return float(s[: -len(suffix)]) * mult
            except ValueError:
                return None
    try:
        return float(s)
    except ValueError:
        return None


def prom_instant_query(base_url: str, query: str, *, timeout: int = 60) -> float | None:
    """Run a Prometheus instant query, returning the first scalar value or None."""
    url = base_url.rstrip("/") + "/api/v1/query?" + urllib.parse.urlencode({"query": query})
    try:
        with urllib.request.urlopen(url, timeout=timeout) as resp:  # noqa: S310 (in-cluster URL)
            payload = json.loads(resp.read().decode())
    except Exception as exc:  # network/JSON errors → fall back to KRR's value
        print(f"# prometheus query failed: {exc}", file=sys.stderr)
        return None
    if payload.get("status") != "success":
        return None
    result = payload.get("data", {}).get("result") or []
    if not result:
        return None
    try:
        return float(result[0]["value"][1])
    except (KeyError, IndexError, ValueError, TypeError):
        return None


def avg_memory_bytes(
    base_url: str,
    namespace: str,
    container: str,
    pods: list,
    *,
    window: str,
) -> float | None:
    """Trailing-average working-set bytes for a container across the workload's pods.

    KRR's simple strategy only ever recommends peak (max-of-window) memory, so to set
    *requests* to the steady-state average we query Prometheus directly, scoped to the
    exact pod names KRR reported for this workload.
    """
    names = [p.get("name") for p in pods if isinstance(p, dict) and p.get("name")]
    if not names:
        return None
    pod_re = "|".join(names)
    query = (
        "avg(avg_over_time(container_memory_working_set_bytes{"
        f'namespace="{namespace}",container="{container}",pod=~"{pod_re}"'
        f"}}[{window}]))"
    )
    return prom_instant_query(base_url, query)


def index_app_template_apps() -> dict[tuple[str, str], tuple[Path, str, str]]:
    """Return {(namespace, deployment_name): (values_path, release, controller_key)}."""
    yaml = YAML(typ="safe")
    index: dict[tuple[str, str], tuple[Path, str, str]] = {}

    for kust in APPS_ROOT.glob("*/*/kustomization.yaml"):
        try:
            kdata = yaml.load(kust.read_text()) or {}
        except Exception:
            continue
        helm_charts = kdata.get("helmCharts") or []
        app_template = next(
            (hc for hc in helm_charts if hc.get("name") == APP_TEMPLATE_CHART),
            None,
        )
        if not app_template:
            continue
        release = app_template.get("releaseName") or app_template.get("name")
        values_file = app_template.get("valuesFile", "values.yaml")
        values_path = kust.parent / values_file
        if not values_path.exists():
            continue
        try:
            vdata = yaml.load(values_path.read_text()) or {}
        except Exception:
            continue
        namespace = kdata.get("namespace") or kust.parent.parent.name
        controllers = vdata.get("controllers") or {}
        for ctrl_key in controllers.keys():
            deployment_name = release if ctrl_key == release else f"{release}-{ctrl_key}"
            index[(namespace, deployment_name)] = (values_path, release, ctrl_key)
            if ctrl_key == release:
                continue
            index.setdefault((namespace, ctrl_key), (values_path, release, ctrl_key))
    return index


def should_change(current, recommended, *, kind: str, min_pct: float, min_abs: float) -> bool:
    if recommended is None:
        return False
    if current is None:
        return True
    if current == 0:
        return recommended > 0
    delta = abs(recommended - current)
    if delta < min_abs:
        return False
    return (delta / current) >= min_pct


def compute_rec(scan: dict, prometheus_url: str | None, avg_window: str) -> tuple[float | None, float | None]:
    """Extract (cpu_cores, memory_bytes) from a KRR scan, overriding memory with
    the trailing-average working set when a Prometheus URL is supplied."""
    obj = scan.get("object") or {}
    rec = (scan.get("recommended") or {}).get("requests") or {}
    rec_cpu = rec.get("cpu", {}).get("value") if isinstance(rec.get("cpu"), dict) else None
    rec_mem = rec.get("memory", {}).get("value") if isinstance(rec.get("memory"), dict) else None
    if prometheus_url:
        avg_mem = avg_memory_bytes(
            prometheus_url, obj.get("namespace"), obj.get("container"), obj.get("pods") or [], window=avg_window
        )
        if isinstance(avg_mem, (int, float)) and avg_mem > 0:
            rec_mem = avg_mem
    return rec_cpu, rec_mem


def apply_to_requests(
    requests,
    rec_cpu,
    rec_mem,
    *,
    path: Path,
    ns: str,
    ctrl: str,
    container: str,
    min_pct: float,
    min_cpu_abs: float,
    min_mem_abs: float,
) -> list[Change]:
    """Patch cpu/memory on a requests mapping in place, returning the changes made."""
    out: list[Change] = []
    if isinstance(rec_cpu, (int, float)):
        current = parse_cpu(requests.get("cpu"))
        if should_change(current, rec_cpu, kind="cpu", min_pct=min_pct, min_abs=min_cpu_abs):
            before, after = str(requests.get("cpu", "<unset>")), fmt_cpu(rec_cpu)
            if before != after:
                requests["cpu"] = after
                out.append(Change(path, ns, ctrl, container, "cpu", before, after))
    if isinstance(rec_mem, (int, float)):
        current = parse_mem(requests.get("memory"))
        if should_change(current, rec_mem, kind="memory", min_pct=min_pct, min_abs=min_mem_abs):
            before, after = str(requests.get("memory", "<unset>")), fmt_mem(rec_mem)
            if before != after:
                requests["memory"] = after
                out.append(Change(path, ns, ctrl, container, "memory", before, after))
    return out


MARKER_RE = re.compile(r"#\s*krr:\s*([^\s#]+)")


def parse_marker(spec: str) -> tuple[str, str, str | None] | None:
    """Parse a marker spec `<workload>/<container>[@<namespace>]`."""
    ns = None
    if "@" in spec:
        spec, ns = spec.rsplit("@", 1)
    if "/" not in spec:
        return None
    name, _, container = spec.partition("/")
    if not name or not container:
        return None
    return name, container, (ns or None)


def resolve_namespace(path: Path) -> str | None:
    """Namespace for a marked file: sibling kustomization's namespace, else the
    category directory (kubernetes/apps/<cluster>/<category>/<app>/...)."""
    kust = path.parent / "kustomization.yaml"
    if kust.exists():
        try:
            kdata = YAML(typ="safe").load(kust.read_text()) or {}
        except Exception:
            kdata = {}
        if kdata.get("namespace"):
            return kdata["namespace"]
    try:
        return path.relative_to(APPS_ROOT).parts[0]
    except ValueError:
        return None


def collect_resource_blocks(node, out: list) -> None:
    """Recursively collect (line, requests_map) for every mapping that holds a
    `requests` child carrying cpu/memory — regardless of the enclosing key name.

    This matches the common `resources: {requests: ...}` shape but also schemas
    that key resources by component, e.g. rook's `resources: {mgr: {requests: ...},
    mon: {requests: ...}}`. `line` is the 0-indexed source line (absolute within
    the document stream) of the key whose value is the resource-bearing mapping
    (the `resources:` / `mgr:` / `server:` line a marker is placed above)."""
    if hasattr(node, "items"):
        lc = getattr(node, "lc", None)
        for k, v in node.items():
            req = v.get("requests") if hasattr(v, "get") else None
            if hasattr(req, "get") and ("cpu" in req or "memory" in req):
                line = lc.data[k][0] if (lc is not None and k in getattr(lc, "data", {})) else None
                out.append((line, req))
            collect_resource_blocks(v, out)
    elif isinstance(node, list):
        for item in node:
            collect_resource_blocks(item, out)


def _marker_yaml() -> YAML:
    yaml = YAML()
    yaml.preserve_quotes = True
    yaml.width = 4096
    yaml.indent(mapping=2, sequence=4, offset=2)
    return yaml


def apply_marker_recommendations(
    scan_index: dict[tuple, dict],
    *,
    skip_paths: set[Path],
    prometheus_url: str | None,
    avg_window: str,
    min_pct: float,
    min_cpu_abs: float,
    min_mem_abs: float,
    dry_run: bool,
) -> tuple[list[Change], list[str]]:
    """Patch resource requests on `# krr: <workload>/<container>`-marked blocks in
    any (non-app-template) YAML under APPS_ROOT."""
    changes: list[Change] = []
    skipped: list[str] = []

    for path in sorted(APPS_ROOT.rglob("*.yaml")):
        if "/charts/" in str(path) or path in skip_paths:
            continue
        text = path.read_text()
        if "krr:" not in text:
            continue

        markers = []
        for lineno, line in enumerate(text.splitlines(), start=1):
            m = MARKER_RE.search(line)
            if not m:
                continue
            parsed = parse_marker(m.group(1))
            if parsed:
                markers.append((lineno, *parsed))
        if not markers:
            continue

        rel = path.relative_to(REPO_ROOT)
        yaml = _marker_yaml()
        try:
            docs = list(yaml.load_all(text))
        except Exception as exc:
            skipped.append(f"{rel}: marker file parse error ({exc})")
            continue

        blocks: list = []
        for doc in docs:
            collect_resource_blocks(doc, blocks)
        blocks = sorted([b for b in blocks if b[0] is not None], key=lambda b: b[0])

        file_changes: list[Change] = []
        for lineno, name, container, marker_ns in markers:
            ns = marker_ns or resolve_namespace(path)
            scan = scan_index.get((ns, name, container))
            if scan is None:
                skipped.append(f"{ns}/{name}/{container}: marker in {rel}:{lineno} has no matching krr scan")
                continue
            # Nearest resources block at or below the marker line.
            cand = [b for b in blocks if b[0] + 1 >= lineno]
            if not cand:
                skipped.append(f"{ns}/{name}/{container}: marker in {rel}:{lineno} has no resources block below it")
                continue
            requests = cand[0][1]
            rec_cpu, rec_mem = compute_rec(scan, prometheus_url, avg_window)
            file_changes += apply_to_requests(
                requests, rec_cpu, rec_mem,
                path=path, ns=ns, ctrl=name, container=container,
                min_pct=min_pct, min_cpu_abs=min_cpu_abs, min_mem_abs=min_mem_abs,
            )

        if file_changes:
            changes += file_changes
            if not dry_run:
                with path.open("w") as f:
                    yaml.dump_all(docs, f)

    return changes, skipped


def apply_recommendations(
    krr_path: Path,
    *,
    min_pct: float,
    min_cpu_abs: float,
    min_mem_abs: float,
    dry_run: bool,
    prometheus_url: str | None = None,
    avg_window: str = "14d",
) -> tuple[list[Change], list[str]]:
    krr = json.loads(krr_path.read_text())
    index = index_app_template_apps()
    changes: list[Change] = []
    skipped: list[str] = []

    # Reverse lookup for the marker pass: (namespace, workload, container) -> scan.
    scan_index: dict[tuple, dict] = {}
    for scan in krr.get("scans", []):
        o = scan.get("object") or {}
        scan_index[(o.get("namespace"), o.get("name"), o.get("container"))] = scan

    # --- Pass 1: app-template charts (auto-discovered) ---
    file_states: dict[Path, tuple[YAML, object]] = {}

    for scan in krr.get("scans", []):
        obj = scan.get("object") or {}
        ns = obj.get("namespace")
        name = obj.get("name")
        container = obj.get("container")

        rec_cpu, rec_mem = compute_rec(scan, prometheus_url, avg_window)
        if not isinstance(rec_cpu, (int, float)) and not isinstance(rec_mem, (int, float)):
            continue

        target = index.get((ns, name))
        if target is None:
            # Not app-template — a marker may still cover it in pass 2.
            skipped.append(f"{ns}/{name}/{container}: no app-template match")
            continue
        values_path, _release, ctrl_key = target

        if values_path not in file_states:
            file_states[values_path] = load_yaml(values_path)
        yaml, vdata = file_states[values_path]

        controller = (vdata.get("controllers") or {}).get(ctrl_key)
        if not controller:
            skipped.append(f"{ns}/{name}/{container}: controller {ctrl_key} missing")
            continue
        containers = controller.get("containers") or {}
        cdef = containers.get(container)
        if cdef is None:
            skipped.append(f"{ns}/{name}/{container}: container missing in values.yaml")
            continue

        resources = cdef.setdefault("resources", {})
        requests = resources.setdefault("requests", {})
        changes += apply_to_requests(
            requests, rec_cpu, rec_mem,
            path=values_path, ns=ns, ctrl=ctrl_key, container=container,
            min_pct=min_pct, min_cpu_abs=min_cpu_abs, min_mem_abs=min_mem_abs,
        )

    if not dry_run:
        for path, (yaml, vdata) in file_states.items():
            if any(c.path == path for c in changes):
                with path.open("w") as f:
                    yaml.dump(vdata, f)

    # --- Pass 2: everything else, via inline `# krr:` markers ---
    marker_changes, marker_skipped = apply_marker_recommendations(
        scan_index,
        skip_paths={t[0] for t in index.values()},
        prometheus_url=prometheus_url,
        avg_window=avg_window,
        min_pct=min_pct,
        min_cpu_abs=min_cpu_abs,
        min_mem_abs=min_mem_abs,
        dry_run=dry_run,
    )
    changes += marker_changes

    # A scan covered by a marker is no longer "skipped" — drop those notes.
    marked_keys = {(c.namespace, c.controller, c.container) for c in marker_changes}
    skipped = [s for s in skipped if not any(s.startswith(f"{ns}/{nm}/{ct}:") for (ns, nm, ct) in marked_keys)]
    skipped += marker_skipped

    return changes, skipped


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("krr_json", type=Path, help="KRR JSON output file")
    ap.add_argument("--min-pct", type=float, default=0.30, help="min relative delta (0.30 = 30%%)")
    ap.add_argument("--min-cpu-abs", type=float, default=0.01, help="min CPU delta in cores (default 10m)")
    ap.add_argument("--min-mem-abs", type=float, default=50 * 1024 * 1024, help="min mem delta in bytes (default 50Mi)")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument(
        "--avg-memory",
        action="store_true",
        help="set memory requests to the trailing-average working set (queried from Prometheus) instead of KRR's peak",
    )
    ap.add_argument("--prometheus-url", default=None, help="Prometheus base URL (required for --avg-memory)")
    ap.add_argument("--avg-window", default="14d", help="averaging window for --avg-memory (default 14d)")
    args = ap.parse_args()

    if args.avg_memory and not args.prometheus_url:
        ap.error("--avg-memory requires --prometheus-url")

    changes, skipped = apply_recommendations(
        args.krr_json,
        min_pct=args.min_pct,
        min_cpu_abs=args.min_cpu_abs,
        min_mem_abs=args.min_mem_abs,
        dry_run=args.dry_run,
        prometheus_url=args.prometheus_url if args.avg_memory else None,
        avg_window=args.avg_window,
    )

    if changes:
        print(f"# {len(changes)} change(s){' (dry-run)' if args.dry_run else ''}\n")
        for c in changes:
            rel = c.path.relative_to(REPO_ROOT)
            print(f"{rel}: {c.namespace}/{c.controller}/{c.container} {c.field}: {c.before} -> {c.after}")
    else:
        print("no changes" + (" (dry-run)" if args.dry_run else ""))

    if skipped:
        print(f"\n# {len(skipped)} skipped (non-app-template or unmatched)", file=sys.stderr)

    return 0


if __name__ == "__main__":
    sys.exit(main())
