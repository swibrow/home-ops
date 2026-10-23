#!/usr/bin/env -S uv run --script
# /// script
# dependencies = ["requests", "pyyaml", "websockets"]
# ///
"""Sync Home Assistant's UI-editable config with iot/homeassistant/ so it can be changed from git or the UI.

Managed through the API: automations, scripts, scenes, helpers (input_*, counter, timer, schedule) and
dashboard configs, plus blueprints (push only, HA has no API to read them back). YAML-only config stays in
packages/ and is copied to the host by hand.

.ha-state.json records a hash of every item as of the last pull or push; that is what tells a UI edit
apart from a local one. Commit it together with the files.

    pull           HA -> git. Keeps local edits that have not been pushed yet.
    diff           Show what push would do.
    push [paths]   git -> HA, then writes HA's normalized result back to the file. Refuses to overwrite an
                   item changed in HA since the last sync (run pull first) unless --force. Deleting a
                   synced file deletes the item.

Env: HA_TOKEN (falls back to HOME_ASSISTANT_TOKEN), HA_URL (default http://homeassistant.iot:8123).
"""
from __future__ import annotations

import hashlib
import itertools
import json
import os
import sys
from pathlib import Path

import requests
import yaml
from websockets.sync.client import connect

HA_URL = os.environ.get("HA_URL", "http://homeassistant.iot:8123")
TOKEN = os.environ.get("HA_TOKEN") or os.environ["HOME_ASSISTANT_TOKEN"]
REPO = Path(__file__).resolve().parent.parent
HA_DIR = Path("iot/homeassistant")
STATE = REPO / HA_DIR / ".ha-state.json"
HELPER_DOMAINS = ["input_boolean", "input_button", "input_datetime", "input_number", "input_select", "input_text",
                  "counter", "timer", "schedule"]
ID_CONFIGS = {"automations": "automation", "scenes": "scene"}
MANAGED = {*ID_CONFIGS, "scripts", "helpers", "dashboards"}
BLUEPRINT_NAMESPACE = "swibrow"


class Dumper(yaml.SafeDumper):
    def increase_indent(self, flow=False, indentless=False):
        return super().increase_indent(flow, False)


def str_presenter(dumper, data):
    style = "|" if "\n" in data else None
    return dumper.represent_scalar("tag:yaml.org,2002:str", data, style=style)


Dumper.add_representer(str, str_presenter)


class BlueprintLoader(yaml.SafeLoader):
    pass


BlueprintLoader.add_constructor("!input", lambda loader, node: loader.construct_scalar(node))


def dump(data) -> str:
    return yaml.dump(data, Dumper=Dumper, sort_keys=False, allow_unicode=True, width=120)


def digest(data) -> str | None:
    if data is None:
        return None
    raw = data if isinstance(data, str) else json.dumps(data, sort_keys=True)
    return hashlib.sha256(raw.encode()).hexdigest()[:16]


class HA:
    def __init__(self, ws):
        self.http = requests.Session()
        self.http.headers["Authorization"] = f"Bearer {TOKEN}"
        self.ws = ws
        self.ws.recv()
        self.ws.send(json.dumps({"type": "auth", "access_token": TOKEN}))
        if json.loads(self.ws.recv())["type"] != "auth_ok":
            raise SystemExit("authentication failed")
        self.ids = itertools.count(1)

    def rest(self, method: str, path: str, **kwargs):
        reply = self.http.request(method, f"{HA_URL}/api/{path}", timeout=30, **kwargs)
        if reply.status_code == 404 and method == "GET":
            return None
        if not reply.ok:
            raise SystemExit(f"{method} {path}: {reply.status_code} {reply.text}")
        return reply.json()

    def call(self, msg_type: str, **kwargs):
        self.ws.send(json.dumps({"id": next(self.ids), "type": msg_type, **kwargs}))
        reply = json.loads(self.ws.recv())
        if not reply["success"]:
            raise SystemExit(f"{msg_type}: {reply['error']}")
        return reply["result"]


def local_items() -> dict:
    items = {}
    for path in (REPO / HA_DIR).rglob("*.yaml"):
        rel = path.relative_to(REPO)
        kind = rel.parts[2]
        if kind not in MANAGED:
            continue
        data = yaml.safe_load(path.read_text())
        if kind in ID_CONFIGS:
            key = f"{kind}/{data['id']}"
        elif kind == "helpers":
            key = f"helpers/{rel.parts[3]}/{data['id']}"
        else:
            key = f"{kind}/{rel.stem}"
        items[key] = (rel, data)
    return items


def remote_items(ha: HA) -> dict:
    items = {}
    states = ha.rest("GET", "states")
    for kind, domain in ID_CONFIGS.items():
        for state in states:
            entity_id = state["entity_id"]
            if entity_id.startswith(f"{domain}.") and "id" in state["attributes"]:
                config = ha.rest("GET", f"config/{domain}/config/{state['attributes']['id']}")
                if config is not None:
                    rel = HA_DIR / kind / f"{entity_id.split('.', 1)[1]}.yaml"
                    items[f"{kind}/{config['id']}"] = (rel, config)
    for state in states:
        if state["entity_id"].startswith("script."):
            object_id = state["entity_id"].split(".", 1)[1]
            config = ha.rest("GET", f"config/script/config/{object_id}")
            if config is not None:
                items[f"scripts/{object_id}"] = (HA_DIR / "scripts" / f"{object_id}.yaml", config)
    for domain in HELPER_DOMAINS:
        for item in ha.call(f"{domain}/list"):
            items[f"helpers/{domain}/{item['id']}"] = (HA_DIR / "helpers" / domain / f"{item['id']}.yaml", item)
    for dash in [{"url_path": None, "mode": "storage"}] + ha.call("lovelace/dashboards/list"):
        if dash["mode"] != "storage":
            continue
        try:
            config = ha.call("lovelace/config", url_path=dash["url_path"], force=True)
        except SystemExit as err:
            if "config_not_found" in str(err):
                continue
            raise
        name = dash["url_path"] or "overview"
        items[f"dashboards/{name}"] = (HA_DIR / "dashboards" / f"{name}.yaml", config)
    return items


def write_remote(ha: HA, key: str, data) -> None:
    kind, _, name = key.partition("/")
    if kind in ID_CONFIGS:
        ha.rest("POST", f"config/{ID_CONFIGS[kind]}/config/{name}", json={k: v for k, v in data.items() if k != "id"})
    elif kind == "scripts":
        ha.rest("POST", f"config/script/config/{name}", json=data)
    elif kind == "helpers":
        domain, item_id = name.split("/")
        fields = {k: v for k, v in data.items() if k != "id"}
        if not any(item["id"] == item_id for item in ha.call(f"{domain}/list")):
            created = ha.call(f"{domain}/create", **{**fields, "name": item_id})
            if created["id"] != item_id:
                raise SystemExit(f"{key}: HA created id {created['id']!r}")
        ha.call(f"{domain}/update", **{f"{domain}_id": item_id}, **fields)
    elif kind == "dashboards":
        ha.call("lovelace/config/save", url_path=None if name == "overview" else name, config=data)


def delete_remote(ha: HA, key: str) -> None:
    kind, _, name = key.partition("/")
    if kind in ID_CONFIGS:
        ha.rest("DELETE", f"config/{ID_CONFIGS[kind]}/config/{name}")
    elif kind == "scripts":
        ha.rest("DELETE", f"config/script/config/{name}")
    elif kind == "helpers":
        domain, item_id = name.split("/")
        ha.call(f"{domain}/delete", **{f"{domain}_id": item_id})
    else:
        raise SystemExit(f"{key}: delete it in the UI")


def load_state() -> dict:
    return json.loads(STATE.read_text()) if STATE.exists() else {}


def save_state(state: dict) -> None:
    STATE.write_text(json.dumps(dict(sorted(state.items())), indent=2) + "\n")


def pull(ha: HA) -> None:
    local, remote, state = local_items(), remote_items(ha), load_state()
    for key, (rel, data) in remote.items():
        old = local.get(key)
        if old and old[1] != data and key in state and digest(old[1]) != state[key]:
            print(f"keep {old[0]}: local edits not pushed yet")
            continue
        state[key] = digest(data)
        if old and old[0] == rel and old[1] == data:
            continue
        if old and old[0] != rel:
            (REPO / old[0]).unlink()
        (REPO / rel).parent.mkdir(parents=True, exist_ok=True)
        (REPO / rel).write_text(dump(data))
        print(f"wrote {rel}")
    for key in local.keys() - remote.keys():
        rel, data = local[key]
        if state.get(key) == digest(data):
            (REPO / rel).unlink()
            del state[key]
            print(f"removed {rel}")
        else:
            print(f"keep {rel}: not in HA, push it or delete it")
    for key in [k for k in state if not k.startswith("blueprints/") and k not in remote and k not in local]:
        del state[key]
    save_state(state)


def plan(ha: HA, paths: list[str], force: bool):
    local, remote, state = local_items(), remote_items(ha), load_state()
    selected = {str(Path(p)) for p in paths}
    changes, conflicts = [], []
    for key in local.keys() | {k for k in state if k.split("/")[0] in MANAGED}:
        rel = local[key][0] if key in local else remote.get(key, (Path(key),))[0]
        if selected and str(rel) not in selected:
            continue
        mine = local.get(key, (None, None))[1]
        theirs = remote.get(key, (None, None))[1]
        if mine == theirs:
            continue
        if digest(theirs) != state.get(key) and not force:
            conflicts.append(rel)
            continue
        changes.append((key, rel, mine))
    blueprints = [rel for path in sorted((REPO / HA_DIR / "blueprints").glob("*.yaml"))
                  for rel in [path.relative_to(REPO)]
                  if (not selected or str(rel) in selected)
                  and digest(path.read_text()) != state.get(f"blueprints/{path.name}")]
    unmanaged = [remote[k][0] for k in remote.keys() - local.keys() - state.keys()]
    return changes, blueprints, conflicts, unmanaged


def report(changes, blueprints, conflicts, unmanaged) -> None:
    for key, rel, mine in changes:
        print(f"{'delete' if mine is None else 'apply'} {rel}")
    for rel in blueprints:
        print(f"blueprint {rel}")
    for rel in conflicts:
        print(f"conflict {rel}: changed in HA since the last sync, run pull (or push --force)")
    for rel in unmanaged:
        print(f"unmanaged {rel}: only in HA, run pull")


def push(ha: HA, paths: list[str], force: bool) -> None:
    changes, blueprints, conflicts, unmanaged = plan(ha, paths, force)
    report(changes, blueprints, conflicts, unmanaged)
    if conflicts:
        raise SystemExit(1)
    state = load_state()
    for rel in blueprints:
        text = (REPO / rel).read_text()
        domain = yaml.load(text, Loader=BlueprintLoader)["blueprint"]["domain"]
        ha.call("blueprint/save", domain=domain, path=f"{BLUEPRINT_NAMESPACE}/{rel.name}", yaml=text,
                allow_override=True)
        ha.rest("POST", f"services/{domain}/reload")
        state[f"blueprints/{rel.name}"] = digest(text)
    for key, rel, mine in changes:
        if mine is None:
            delete_remote(ha, key)
            state.pop(key, None)
        else:
            write_remote(ha, key, mine)
    if changes:
        remote = remote_items(ha)
        for key, rel, mine in changes:
            if mine is not None and key in remote:
                state[key] = digest(remote[key][1])
                if remote[key][1] != mine:
                    (REPO / rel).write_text(dump(remote[key][1]))
    save_state(state)


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if a != "--force"]
    if not args or args[0] not in {"pull", "diff", "push"} or (args[0] != "push" and len(args) > 1):
        raise SystemExit(__doc__)
    with connect(HA_URL.replace("http", "ws", 1) + "/api/websocket", max_size=None) as ws:
        ha = HA(ws)
        match args:
            case ["pull"]:
                pull(ha)
            case ["diff"]:
                report(*plan(ha, [], False))
            case ["push", *paths]:
                push(ha, paths, "--force" in sys.argv)
