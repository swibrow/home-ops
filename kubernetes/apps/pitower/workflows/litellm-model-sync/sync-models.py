#!/usr/bin/env python3
import os
import subprocess
import time

import requests
import yaml

REPO_DIR = "/work/home-ops"
REPO_HOST_PATH = "github.com/swibrow/home-ops.git"
CONFIG_REL_PATH = "kubernetes/apps/pitower/ai/litellm/config.yaml"
BRANCH = "automation/litellm-model-sync"
LOOKBACK_DAYS = int(os.environ.get("LOOKBACK_DAYS", "14"))
GITHUB_TOKEN = os.environ["GITHUB_TOKEN"]
CATALOG_MARKER = "  # --- OpenRouter (catch-all passthrough) ---"


def run(*args, cwd=None):
    return subprocess.run(args, cwd=cwd, check=True, capture_output=True, text=True)


def git_clone():
    url = f"https://x-access-token:{GITHUB_TOKEN}@{REPO_HOST_PATH}"
    run("git", "clone", "--depth", "50", url, REPO_DIR)
    run("git", "config", "user.name", "litellm-model-sync", cwd=REPO_DIR)
    run("git", "config", "user.email", "actions@wibrow.dev", cwd=REPO_DIR)


def load_existing(config_path):
    with open(config_path) as f:
        text = f.read()
    doc = yaml.safe_load(text)
    existing_ids = set()
    providers = set()
    for entry in doc.get("model_list", []):
        model = entry.get("litellm_params", {}).get("model", "")
        if model.startswith("openrouter/") and model != "openrouter/*":
            slug = model[len("openrouter/"):]
            existing_ids.add(slug)
            providers.add(slug.split("/", 1)[0])
    return text, existing_ids, providers


def fetch_catalog():
    resp = requests.get("https://openrouter.ai/api/v1/models", timeout=30)
    resp.raise_for_status()
    return resp.json()["data"]


def find_candidates(catalog, existing_ids, providers):
    cutoff = time.time() - LOOKBACK_DAYS * 86400
    candidates = []
    for m in catalog:
        model_id = m.get("id", "")
        if "/" not in model_id or model_id.endswith(":free"):
            continue
        provider = model_id.split("/", 1)[0]
        if provider not in providers or model_id in existing_ids:
            continue
        if m.get("created", 0) < cutoff:
            continue
        candidates.append(m)
    candidates.sort(key=lambda m: m["id"])
    return candidates


def render_entries(candidates):
    lines = []
    for m in candidates:
        model_name = m["id"].split("/", 1)[1]
        lines.append(f"  - model_name: {model_name}")
        lines.append("    litellm_params:")
        lines.append(f"      model: openrouter/{m['id']}")
        lines.append("      api_key: os.environ/OPENROUTER_API_KEY")
    return "\n".join(lines) + "\n"


def pr_body(candidates):
    lines = [
        f"Auto-detected new models on OpenRouter from providers already tracked in "
        f"`{CONFIG_REL_PATH}`, first seen on OpenRouter within the last {LOOKBACK_DAYS} days.",
        "",
        "| Model | Context | Prompt $/M | Completion $/M |",
        "|---|---|---|---|",
    ]
    for m in candidates:
        pricing = m.get("pricing", {})
        prompt_price = float(pricing.get("prompt", 0) or 0) * 1_000_000
        completion_price = float(pricing.get("completion", 0) or 0) * 1_000_000
        lines.append(
            f"| `{m['id']}` | {m.get('context_length', '?')} | "
            f"${prompt_price:.2f} | ${completion_price:.2f} |"
        )
    return "\n".join(lines)


def open_or_update_pr(title, body):
    headers = {
        "Authorization": f"Bearer {GITHUB_TOKEN}",
        "Accept": "application/vnd.github+json",
    }
    api = "https://api.github.com/repos/swibrow/home-ops"
    resp = requests.get(
        f"{api}/pulls",
        headers=headers,
        params={"head": f"swibrow:{BRANCH}", "state": "open"},
        timeout=30,
    )
    resp.raise_for_status()
    open_prs = resp.json()
    if open_prs:
        number = open_prs[0]["number"]
        r = requests.patch(
            f"{api}/pulls/{number}",
            headers=headers,
            json={"title": title, "body": body},
            timeout=30,
        )
        r.raise_for_status()
        print(f"updated PR #{number}")
    else:
        r = requests.post(
            f"{api}/pulls",
            headers=headers,
            json={"title": title, "body": body, "head": BRANCH, "base": "main"},
            timeout=30,
        )
        r.raise_for_status()
        print(f"opened PR #{r.json()['number']}")


def main():
    git_clone()
    config_path = os.path.join(REPO_DIR, CONFIG_REL_PATH)
    text, existing_ids, providers = load_existing(config_path)

    candidates = find_candidates(fetch_catalog(), existing_ids, providers)
    if not candidates:
        print("no new top-tier models found")
        return

    print(f"found {len(candidates)} candidate model(s):")
    for m in candidates:
        print(f"  {m['id']}")

    idx = text.index(CATALOG_MARKER)
    new_text = text[:idx] + render_entries(candidates) + "\n" + text[idx:]
    with open(config_path, "w") as f:
        f.write(new_text)

    run("git", "checkout", "-B", BRANCH, cwd=REPO_DIR)
    run("git", "add", CONFIG_REL_PATH, cwd=REPO_DIR)
    title = f"feat(litellm): add {len(candidates)} new model(s) from OpenRouter"
    run("git", "commit", "-m", title, cwd=REPO_DIR)
    run("git", "push", "-f", "origin", BRANCH, cwd=REPO_DIR)

    open_or_update_pr(title, pr_body(candidates))


if __name__ == "__main__":
    main()
