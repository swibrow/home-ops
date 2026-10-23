#!/usr/bin/env -S uv run --script
# /// script
# dependencies = ["websockets", "pyyaml"]
# ///
"""Snapshot Home Assistant's storage-mode (UI/API-managed) dashboards into git for review.

Dashboards are edited in the HA UI or through the API; HA's storage is the source of
truth. This writes each one to iot/homeassistant/dashboards/<url_path>.yaml (the default
dashboard as overview.yaml) and removes snapshots of dashboards that no longer exist.
YAML-mode dashboards and auto-generated ones with no saved config are skipped.

Usage:
    export HA_TOKEN=$(kubectl -n ai get secret toolhive-secret -o jsonpath='{.data.HA_TOKEN}' | base64 -d)
    ./scripts/ha-dashboards-export.py
"""
from __future__ import annotations

import asyncio
import itertools
import json
import os
from pathlib import Path

import websockets
import yaml

HA_URL = os.environ.get("HA_URL", "http://homeassistant.iot:8123")
OUT_DIR = Path(__file__).resolve().parent.parent / "iot/homeassistant/dashboards"


class Dumper(yaml.SafeDumper):
    def increase_indent(self, flow=False, indentless=False):
        return super().increase_indent(flow, False)


def str_presenter(dumper, data):
    style = "|" if "\n" in data else None
    return dumper.represent_scalar("tag:yaml.org,2002:str", data, style=style)


Dumper.add_representer(str, str_presenter)


async def main() -> None:
    ws_url = HA_URL.replace("http", "ws", 1) + "/api/websocket"
    ids = itertools.count(1)
    async with websockets.connect(ws_url, max_size=None) as ws:
        await ws.recv()
        await ws.send(json.dumps({"type": "auth", "access_token": os.environ["HA_TOKEN"]}))
        if json.loads(await ws.recv())["type"] != "auth_ok":
            raise SystemExit("authentication failed")

        async def call(msg_type: str, **kwargs):
            await ws.send(json.dumps({"id": next(ids), "type": msg_type, **kwargs}))
            reply = json.loads(await ws.recv())
            if reply["success"]:
                return reply["result"]
            if reply["error"]["code"] == "config_not_found":
                return None
            raise SystemExit(f"{msg_type} {kwargs}: {reply['error']}")

        dashboards = [{"url_path": None, "mode": "storage"}] + await call("lovelace/dashboards/list")
        written = set()
        for dash in dashboards:
            if dash["mode"] != "storage":
                continue
            config = await call("lovelace/config", url_path=dash["url_path"], force=True)
            if config is None:
                continue
            path = OUT_DIR / f"{dash['url_path'] or 'overview'}.yaml"
            path.write_text(yaml.dump(config, Dumper=Dumper, sort_keys=False, allow_unicode=True, width=120))
            written.add(path)
            print(f"wrote {path.relative_to(OUT_DIR.parent.parent.parent)}")

    for stale in set(OUT_DIR.glob("*.yaml")) - written:
        stale.unlink()
        print(f"removed {stale.name}")


asyncio.run(main())
