#!/usr/bin/env python3
"""Tail VictoriaLogs for containers logging without a structured `level` field.

fluent-bit (kubernetes/apps/pitower/monitoring/fluent-bit) only promotes a
`level` field when a container emits single-line JSON with a "level" key.
Plain text, logfmt, and multi-line output all stay unstructured inside `_msg`,
so LogsQL/Grafana can't filter those containers by severity.

This opens a live tail against VictoriaLogs (`NOT level:*`), and the first
time it sees a namespace/container pair in this run, hands a few sample log
lines to a read-only headless Claude Code agent that identifies the app in
this repo, explains why the level isn't structured, and proposes a fix (or
says none is needed, e.g. access logs / a vendored binary with no concept of
level). Each namespace/container pair triggers at most once per run — restart
the script to re-scan.

Requires a kubeconfig context that can reach the cluster; manages its own
`kubectl port-forward` to victoria-logs unless --endpoint is given.

Usage:
    ./scripts/log_level_audit.py                      # tail until Ctrl-C
    ./scripts/log_level_audit.py --max-services 5      # stop after 5 findings
    ./scripts/log_level_audit.py --dry-run             # list services only, no agent calls
    ./scripts/log_level_audit.py --out report.md       # also append findings to a file
"""

from __future__ import annotations

import argparse
import http.client
import json
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_CONTEXT = "admin@pitower"
DEFAULT_NAMESPACE = "monitoring"
DEFAULT_SERVICE = "victoria-logs"
DEFAULT_REMOTE_PORT = 9428
QUERY = "NOT level:*"
SAMPLE_MAX_CHARS = 300

PROMPT_TEMPLATE = """\
You are auditing structured logging for a Kubernetes home-lab GitOps repo \
(Talos + ArgoCD + Helm; apps live under kubernetes/apps/pitower/<category>/<app>/).

VictoriaLogs is receiving log lines from the container below with NO structured \
`level` field. fluent-bit only promotes a `level` field when a container emits \
single-line JSON with a "level" key; plain text, logfmt, and multi-line output all \
stay unstructured inside `_msg`.

Container: {container}
Namespace: {namespace}
Pod: {pod}

Sample raw log line(s) (from `_msg`):
{samples}

Task:
1. Identify which app this is in this repo. Look under kubernetes/apps/pitower/**; \
the container name usually matches a controller/container key in that app's \
values.yaml, but confirm by reading the relevant values.yaml/kustomization.yaml.
2. Determine why the level isn't structured: JSON logging isn't supported by the \
app, JSON logging exists but isn't enabled/configured, the app only logs \
logfmt/plain text, or this is expected (e.g. raw access logs, a vendored binary \
with no concept of level).
3. If a fix is reasonable, propose the smallest concrete change (e.g. a values.yaml \
env var/arg enabling JSON logs). Do NOT edit any files — only propose.
4. If no reasonable fix exists, say so plainly instead of forcing one.

Respond in exactly this markdown shape, nothing else:

### {namespace}/{container}
**App:** <path under kubernetes/apps/pitower/... or "not found in repo">
**Root cause:** <one sentence>
**Proposed fix:** <one or two sentences, or "none — expected">
"""


@dataclass
class ServiceKey:
    namespace: str
    container: str

    def __str__(self) -> str:
        return f"{self.namespace}/{self.container}"


@dataclass
class Pending:
    pod: str
    samples: list[str] = field(default_factory=list)


def log(msg: str) -> None:
    ts = datetime.now(timezone.utc).strftime("%H:%M:%S")
    print(f"[{ts}] {msg}", file=sys.stderr, flush=True)


def start_port_forward(context: str, namespace: str, service: str, local_port: int) -> subprocess.Popen:
    proc = subprocess.Popen(
        [
            "kubectl",
            f"--context={context}",
            "-n",
            namespace,
            "port-forward",
            f"svc/{service}",
            f"{local_port}:{DEFAULT_REMOTE_PORT}",
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    deadline = time.monotonic() + 15
    assert proc.stdout is not None
    while time.monotonic() < deadline:
        line = proc.stdout.readline()
        if not line:
            if proc.poll() is not None:
                raise RuntimeError("kubectl port-forward exited before it was ready")
            continue
        if "Forwarding from" in line:
            return proc
    proc.terminate()
    raise RuntimeError("timed out waiting for kubectl port-forward to become ready")


def tail_entries(base_url: str, query: str, timeout: float | None = None):
    """Yield decoded log entries from a live VictoriaLogs tail.

    `timeout` bounds each individual socket read, not the whole stream — if
    the connection goes silent for that long (kubectl port-forward tunnels are
    known to hang like this on long-lived streams) it raises so the caller can
    reconnect, instead of blocking forever on a dead socket.
    """
    url = f"{base_url}/select/logsql/tail"
    data = urllib.parse.urlencode({"query": query}).encode()
    req = urllib.request.Request(url, data=data, method="POST")
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        for raw_line in resp:
            line = raw_line.decode("utf-8", "replace").strip()
            if not line:
                continue
            try:
                yield json.loads(line)
            except json.JSONDecodeError:
                continue


def sample_text(entry: dict) -> str:
    msg = entry.get("_msg") or entry.get("msg") or ""
    msg = " ".join(msg.split())
    if len(msg) > SAMPLE_MAX_CHARS:
        msg = msg[:SAMPLE_MAX_CHARS] + "…"
    return msg


def build_prompt(key: ServiceKey, pod: str, samples: list[str]) -> str:
    numbered = "\n".join(f"{i + 1}. {s}" for i, s in enumerate(samples) if s) or "(no message text captured)"
    return PROMPT_TEMPLATE.format(
        container=key.container,
        namespace=key.namespace,
        pod=pod,
        samples=numbered,
    )


def investigate(key: ServiceKey, pod: str, samples: list[str], model: str | None, timeout: int) -> str:
    prompt = build_prompt(key, pod, samples)
    cmd = [
        "claude",
        "-p",
        prompt,
        "--allowedTools",
        "Read Glob Grep",
        "--output-format",
        "text",
    ]
    if model:
        cmd += ["--model", model]
    try:
        result = subprocess.run(
            cmd,
            cwd=REPO_ROOT,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired:
        return f"### {key}\n**App:** (timed out)\n**Root cause:** agent investigation exceeded {timeout}s\n**Proposed fix:** rerun manually\n"

    if result.returncode != 0:
        err = (result.stderr or "unknown error").strip()
        return f"### {key}\n**App:** (agent error)\n**Root cause:** claude exited {result.returncode}: {err[:300]}\n**Proposed fix:** rerun manually\n"

    return result.stdout.strip() + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--context", default=DEFAULT_CONTEXT, help="kubeconfig context (default: %(default)s)")
    parser.add_argument("--namespace", default=DEFAULT_NAMESPACE, help="namespace of the victoria-logs Service")
    parser.add_argument("--service", default=DEFAULT_SERVICE, help="Service name to port-forward")
    parser.add_argument("--local-port", type=int, default=19428, help="local port for kubectl port-forward")
    parser.add_argument("--endpoint", help="use an existing VictoriaLogs endpoint instead of port-forwarding, e.g. http://localhost:9428")
    parser.add_argument("--stall-timeout", type=float, default=90.0, help="reconnect if the tail goes silent this long, in seconds (default: %(default)s)")
    parser.add_argument("--max-services", type=int, default=None, help="stop after investigating this many services")
    parser.add_argument("--buffer-seconds", type=float, default=2.0, help="collect sample lines for a service this long before dispatching (default: %(default)s)")
    parser.add_argument("--max-samples", type=int, default=5, help="max sample log lines passed to the agent")
    parser.add_argument("--concurrency", type=int, default=2, help="max concurrent agent investigations")
    parser.add_argument("--timeout", type=int, default=300, help="per-agent timeout in seconds")
    parser.add_argument("--model", help="model override passed to claude -p")
    parser.add_argument("--dry-run", action="store_true", help="print detected services and samples, skip agent calls")
    parser.add_argument("--out", type=Path, help="append findings to this markdown file as they arrive")
    args = parser.parse_args()

    out_fh = None
    if args.out:
        out_fh = args.out.open("a")
        out_fh.write(f"\n## Run {datetime.now(timezone.utc).isoformat()}\n\n")
        out_fh.flush()

    lock = threading.Lock()
    seen: set[tuple[str, str]] = set()
    pending: dict[tuple[str, str], Pending] = {}
    timers: dict[tuple[str, str], threading.Timer] = {}
    done = threading.Event()
    count = 0

    executor = ThreadPoolExecutor(max_workers=max(1, args.concurrency))

    def report(text: str) -> None:
        print(text)
        if out_fh:
            out_fh.write(text + "\n")
            out_fh.flush()

    def dispatch(key_tuple: tuple[str, str]) -> None:
        nonlocal count
        if done.is_set():
            return
        with lock:
            if key_tuple in seen or done.is_set():
                return
            if args.max_services and count >= args.max_services:
                done.set()
                return
            seen.add(key_tuple)
            p = pending.pop(key_tuple, None)
            timers.pop(key_tuple, None)
            count += 1
            current = count
            if args.max_services and current >= args.max_services:
                done.set()

        if p is None:
            return
        key = ServiceKey(*key_tuple)
        log(f"[{current}] investigating {key} ({len(p.samples)} sample line(s))")

        if args.dry_run:
            report(f"### {key} (dry-run)\nPod: {p.pod}\nSamples:\n" + "\n".join(f"- {s}" for s in p.samples))
        else:
            report(investigate(key, p.pod, p.samples, args.model, args.timeout))

        if args.max_services and current >= args.max_services:
            done.set()

    def on_entry(entry: dict) -> None:
        namespace = entry.get("kubernetes_namespace_name")
        container = entry.get("kubernetes_container_name")
        pod = entry.get("kubernetes_pod_name", "")
        if not namespace or not container:
            return
        key_tuple = (namespace, container)
        with lock:
            if key_tuple in seen:
                return
            p = pending.setdefault(key_tuple, Pending(pod=pod))
            if len(p.samples) < args.max_samples:
                p.samples.append(sample_text(entry))
            if key_tuple not in timers:
                t = threading.Timer(args.buffer_seconds, lambda kt=key_tuple: executor.submit(dispatch, kt))
                timers[key_tuple] = t
                t.start()

    pf_proc = None
    reconnect_errors = 0
    max_consecutive_reconnect_errors = 10
    exit_code = 0
    try:
        while not done.is_set():
            try:
                if args.endpoint:
                    base_url = args.endpoint.rstrip("/")
                else:
                    if pf_proc:
                        pf_proc.terminate()
                        pf_proc.wait()
                    log(f"port-forwarding svc/{args.service} in {args.namespace} (context {args.context})")
                    pf_proc = start_port_forward(args.context, args.namespace, args.service, args.local_port)
                    base_url = f"http://127.0.0.1:{args.local_port}"

                log(f"tailing VictoriaLogs at {base_url} with query: {QUERY}")
                for entry in tail_entries(base_url, QUERY, timeout=args.stall_timeout):
                    on_entry(entry)
                    reconnect_errors = 0
                    if done.is_set():
                        break
                if not done.is_set():
                    log("tail stream ended, reconnecting")
            except (OSError, urllib.error.URLError, http.client.HTTPException, RuntimeError) as e:
                if done.is_set():
                    break
                reconnect_errors += 1
                if reconnect_errors > max_consecutive_reconnect_errors:
                    log(f"giving up after {reconnect_errors} consecutive reconnect failures: {e}")
                    exit_code = 1
                    break
                log(f"tail connection lost ({e}), reconnecting in 3s (attempt {reconnect_errors})")
                time.sleep(3)
    except KeyboardInterrupt:
        log("interrupted")
    finally:
        for t in list(timers.values()):
            t.cancel()
        executor.shutdown(wait=True)
        if pf_proc:
            pf_proc.terminate()
        if out_fh:
            out_fh.close()

    log(f"done — {count} service(s) investigated this run")
    return exit_code


if __name__ == "__main__":
    sys.exit(main())
