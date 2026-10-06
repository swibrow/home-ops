#!/usr/bin/env python3
# Reference copy only. Not deployed via kustomize/configMap — live copy is
# kubectl cp'd to /opt/data/scripts/alertmanager_new.py on the hermes PVC, and
# the 5m alert-triage cron job (id f9d751f5de83, --script alertmanager_new.py
# --deliver telegram) is registered via `hermes cron create`. A fresh PVC needs
# both steps redone.
#
# Cron pre-check for alert-triage: wakes the agent only when an
# (alertname, namespace) pair starts firing that has not fired within
# COOLDOWN_SECONDS. Keying on the pair rather than the fingerprint stops
# per-object labels (job_name, snapshot name) and flapping alerts from waking
# the agent on every occurrence.
import json
import os
import sys
import time
import urllib.request

ALERTMANAGER_URL = "http://alertmanager-operated.monitoring.svc.cluster.local:9093"
STATE_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "alertmanager_new_state.json")
COOLDOWN_SECONDS = 6 * 3600
IGNORED_SEVERITIES = {"none", "info"}
DETAIL_LABELS = ("pod", "job", "job_name", "instance", "node", "service", "deployment", "statefulset", "name")


def key_of(alert):
    labels = alert.get("labels", {})
    return f"{labels.get('alertname')}|{labels.get('namespace', '-')}"


def load_state():
    try:
        with open(STATE_PATH) as f:
            state = json.load(f)
    except (OSError, ValueError):
        return None
    return state if isinstance(state, dict) else None


def main():
    url = f"{ALERTMANAGER_URL}/api/v2/alerts?active=true&silenced=false&inhibited=false"
    with urllib.request.urlopen(url, timeout=15) as resp:
        alerts = json.loads(resp.read())

    firing = [a for a in alerts if a.get("labels", {}).get("severity") not in IGNORED_SEVERITIES]
    now = time.time()
    state = load_state()
    # Missing or old-format state: record what is firing without waking, so a
    # fresh PVC or the switch from fingerprint state does not replay everything.
    seeding = state is None
    last_seen = {k: t for k, t in (state or {}).items() if now - t < COOLDOWN_SECONDS}

    new_keys = set()
    for a in firing:
        k = key_of(a)
        if k not in last_seen:
            new_keys.add(k)
    for a in firing:
        last_seen[key_of(a)] = now

    with open(STATE_PATH, "w") as f:
        json.dump(last_seen, f, indent=0, sort_keys=True)

    if seeding or not new_keys:
        print(json.dumps({"wakeAgent": False}))
        return

    print("Newly firing:")
    for k in sorted(new_keys):
        group = [a for a in firing if key_of(a) == k]
        a = group[0]
        labels = a.get("labels", {})
        annotations = a.get("annotations", {})
        more = f" (+{len(group) - 1} more like it)" if len(group) > 1 else ""
        print(f"- {labels.get('alertname')} severity={labels.get('severity', '?')} "
              f"namespace={labels.get('namespace', '-')} since={a.get('startsAt')}{more}")
        for key in DETAIL_LABELS:
            if key in labels:
                print(f"    {key}={labels[key]}")
        summary = annotations.get("summary") or annotations.get("description")
        if summary:
            print(f"    summary: {summary[:300]}")

    others = sorted({key_of(a) for a in firing} - new_keys)
    if others:
        print("Already firing (context only, already reported):")
        for k in others:
            alertname, namespace = k.split("|", 1)
            count = sum(1 for a in firing if key_of(a) == k)
            print(f"- {alertname} namespace={namespace} x{count}")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"alertmanager_new failed: {exc}", file=sys.stderr)
        sys.exit(1)
