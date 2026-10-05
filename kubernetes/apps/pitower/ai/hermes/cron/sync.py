"""Reconcile cron/jobs.yaml into Hermes' cron store before the gateway starts.

Runs as an init container from the hermes image, so it uses Hermes' own cron API
(validation, locking, next-run computation) instead of writing jobs.json directly.
Ownership is tracked by name in $HERMES_HOME/cron/gitops.json: only jobs listed
there are updated or removed.
"""

import hashlib
import json
import os
import sys
from pathlib import Path

import yaml

from cron.jobs import create_job, get_job, remove_job, update_job

SPEC_FIELDS = ("prompt", "skills", "script", "no_agent", "enabled_toolsets", "deliver", "context_from")


def desired_jobs(path):
    jobs = yaml.safe_load(Path(path).read_text())["jobs"]
    names = [j["name"] for j in jobs]
    if len(names) != len(set(names)):
        sys.exit(f"duplicate job names in {path}")
    return jobs


def fingerprint(spec):
    return hashlib.sha256(json.dumps(spec, sort_keys=True).encode()).hexdigest()


def main(jobs_path):
    state_path = Path(os.environ["HERMES_HOME"]) / "cron" / "gitops.json"
    state = json.loads(state_path.read_text()) if state_path.exists() else {}
    jobs = desired_jobs(jobs_path)
    wanted = {j["name"] for j in jobs}

    for name in sorted(set(state) - wanted):
        remove_job(state.pop(name)["id"])
        print(f"removed {name}")

    for j in jobs:
        name = j["name"]
        context_from = [state[ref]["id"] for ref in j.get("context_from", [])]
        if j.get("continuity"):
            context_from.append("self")
        spec = {
            "schedule": j["schedule"],
            "prompt": j.get("prompt", "").strip(),
            "skills": j.get("skills") or [],
            "script": j.get("script"),
            "no_agent": bool(j.get("no_agent")),
            "enabled_toolsets": j.get("enabled_toolsets"),
            "deliver": j.get("deliver", "telegram"),
            "context_from": context_from or None,
        }
        digest = fingerprint(spec)
        current = state.get(name)

        if current and get_job(current["id"]):
            if current["hash"] == digest:
                continue
            update_job(current["id"], {k: spec[k] for k in ("schedule", *SPEC_FIELDS)})
            print(f"updated {name}")
        else:
            current = {"id": create_job(name=name, **spec)["id"]}
            print(f"created {name}")
        current["hash"] = digest
        state[name] = current

    state_path.parent.mkdir(parents=True, exist_ok=True)
    state_path.write_text(json.dumps(state, indent=2, sort_keys=True))


if __name__ == "__main__":
    main(sys.argv[1])
