#!/usr/bin/env python3
"""Apply KRR recommendations to app-template values.yaml files.

Reads KRR JSON output, locates the corresponding values.yaml under
kubernetes/apps/pitower/<namespace>/<app>/, and updates
controllers.<ctrl>.containers.<container>.resources.requests.{cpu,memory}.

Skips workloads that aren't bjw-s-labs/app-template charts and any
delta below the configured thresholds.
"""

from __future__ import annotations

import argparse
import json
import math
import sys
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


def apply_recommendations(
    krr_path: Path,
    *,
    min_pct: float,
    min_cpu_abs: float,
    min_mem_abs: float,
    dry_run: bool,
) -> tuple[list[Change], list[str]]:
    krr = json.loads(krr_path.read_text())
    index = index_app_template_apps()
    changes: list[Change] = []
    skipped: list[str] = []

    file_states: dict[Path, tuple[YAML, object]] = {}

    for scan in krr.get("scans", []):
        obj = scan.get("object") or {}
        ns = obj.get("namespace")
        name = obj.get("name")
        container = obj.get("container")
        rec = (scan.get("recommended") or {}).get("requests") or {}
        rec_cpu = rec.get("cpu", {}).get("value") if isinstance(rec.get("cpu"), dict) else None
        rec_mem = rec.get("memory", {}).get("value") if isinstance(rec.get("memory"), dict) else None
        if not isinstance(rec_cpu, (int, float)) and not isinstance(rec_mem, (int, float)):
            continue

        target = index.get((ns, name))
        if target is None:
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

        if isinstance(rec_cpu, (int, float)):
            current = parse_cpu(requests.get("cpu"))
            if should_change(current, rec_cpu, kind="cpu", min_pct=min_pct, min_abs=min_cpu_abs):
                before = str(requests.get("cpu", "<unset>"))
                after = fmt_cpu(rec_cpu)
                if before != after:
                    requests["cpu"] = after
                    changes.append(Change(values_path, ns, ctrl_key, container, "cpu", before, after))

        if isinstance(rec_mem, (int, float)):
            current = parse_mem(requests.get("memory"))
            if should_change(current, rec_mem, kind="memory", min_pct=min_pct, min_abs=min_mem_abs):
                before = str(requests.get("memory", "<unset>"))
                after = fmt_mem(rec_mem)
                if before != after:
                    requests["memory"] = after
                    changes.append(Change(values_path, ns, ctrl_key, container, "memory", before, after))

    if not dry_run:
        for path, (yaml, vdata) in file_states.items():
            if any(c.path == path for c in changes):
                with path.open("w") as f:
                    yaml.dump(vdata, f)

    return changes, skipped


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("krr_json", type=Path, help="KRR JSON output file")
    ap.add_argument("--min-pct", type=float, default=0.30, help="min relative delta (0.30 = 30%%)")
    ap.add_argument("--min-cpu-abs", type=float, default=0.01, help="min CPU delta in cores (default 10m)")
    ap.add_argument("--min-mem-abs", type=float, default=50 * 1024 * 1024, help="min mem delta in bytes (default 50Mi)")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    changes, skipped = apply_recommendations(
        args.krr_json,
        min_pct=args.min_pct,
        min_cpu_abs=args.min_cpu_abs,
        min_mem_abs=args.min_mem_abs,
        dry_run=args.dry_run,
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
