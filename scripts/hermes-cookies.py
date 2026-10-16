#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.12"
# dependencies = ["cryptography", "websockets"]
# ///
"""Copy Chrome cookies for chosen sites from this Mac into hermes' signed-in browser.

Reads the active Chrome profile's cookie store, decrypts the cookies with the
"Chrome Safe Storage" Keychain key (macOS asks for permission), and loads them into
the `browser` sidecar of the hermes pod over a kubectl port-forward. The sidecar
keeps them in its profile on the hermes PVC. Cookie values are never printed.

Usage:
    just hermes::copy-cookies autoscout24.ch digitec.ch
    just hermes::cookie-hosts digitec      # which cookie hosts a login uses
"""

import argparse
import asyncio
import hashlib
import json
import os
import socket
import sqlite3
import subprocess
import sys
import time
import urllib.request
from pathlib import Path

import websockets
from cryptography.hazmat.primitives import padding
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes

CHROME = Path.home() / "Library/Application Support/Google/Chrome"
CHROME_EPOCH_OFFSET = 11644473600
SAME_SITE = {0: "None", 1: "Lax", 2: "Strict"}


def chrome_key():
    password = subprocess.run(
        ["security", "find-generic-password", "-w", "-s", "Chrome Safe Storage"],
        capture_output=True, text=True, check=True,
    ).stdout.strip()
    return hashlib.pbkdf2_hmac("sha1", password.encode(), b"saltysalt", 1003, 16)


def decrypt(key, host, encrypted):
    if encrypted[:3] != b"v10":
        raise ValueError(f"unsupported cookie encryption {encrypted[:3]!r}")
    decryptor = Cipher(algorithms.AES(key), modes.CBC(b" " * 16)).decryptor()
    padded = decryptor.update(encrypted[3:]) + decryptor.finalize()
    unpadder = padding.PKCS7(128).unpadder()
    plain = unpadder.update(padded) + unpadder.finalize()
    # Newer cookie stores prefix each value with the SHA-256 of its host.
    if plain[:32] == hashlib.sha256(host.encode()).digest():
        plain = plain[32:]
    return plain.decode()


def open_store(profile):
    # The online backup reads a consistent copy while Chrome keeps the file open.
    live = sqlite3.connect(f"file:{CHROME / profile / 'Cookies'}?mode=ro", uri=True)
    store = sqlite3.connect(":memory:")
    live.backup(store)
    live.close()
    return store


def active_profile():
    return json.loads((CHROME / "Local State").read_text())["profile"]["last_used"]


def matches(host, domains):
    bare = host.lstrip(".")
    return any(bare == d or bare.endswith("." + d) for d in domains)


def read_cookies(store, domains):
    columns = {row[1] for row in store.execute("pragma table_info(cookies)")}
    partitioned = "top_frame_site_key" if "top_frame_site_key" in columns else "''"
    rows = store.execute(
        "select host_key, name, value, encrypted_value, path, expires_utc, is_secure,"
        f" is_httponly, samesite, {partitioned} from cookies"
    )
    key = None
    cookies = []
    for host, name, value, encrypted, path, expires, secure, httponly, samesite, partition in rows:
        if partition or not matches(host, domains):
            continue
        if not value:
            key = key or chrome_key()
            value = decrypt(key, host, encrypted)
        cookie = {"name": name, "value": value, "path": path, "secure": bool(secure), "httpOnly": bool(httponly)}
        if host.startswith("."):
            cookie["domain"] = host
        else:
            cookie["url"] = f"{'https' if secure else 'http'}://{host}{path}"
        if expires:
            cookie["expires"] = expires / 1_000_000 - CHROME_EPOCH_OFFSET
        if samesite in SAME_SITE:
            cookie["sameSite"] = SAME_SITE[samesite]
        cookies.append((host, cookie))
    return cookies


def free_port():
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


async def load(ws_url, cookies):
    async with websockets.connect(ws_url, max_size=None) as ws:
        await ws.send(json.dumps({"id": 1, "method": "Storage.setCookies", "params": {"cookies": cookies}}))
        reply = json.loads(await ws.recv())
    if "error" in reply:
        sys.exit(f"Storage.setCookies failed: {reply['error'].get('message')}")


def push(cookies, context, namespace):
    port = free_port()
    forward = subprocess.Popen(
        ["kubectl", "--context", context, "-n", namespace, "port-forward", "deploy/hermes", f"{port}:9222"],
        stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
    )
    try:
        for _ in range(30):
            try:
                version = json.load(urllib.request.urlopen(f"http://127.0.0.1:{port}/json/version", timeout=2))
                break
            except OSError:
                if forward.poll() is not None:
                    sys.exit(f"kubectl port-forward failed: {forward.stderr.read().decode().strip()}")
                time.sleep(1)
        else:
            sys.exit("hermes browser sidecar did not answer on port 9222")
        ws_url = version["webSocketDebuggerUrl"].replace("127.0.0.1:9222", f"127.0.0.1:{port}")
        asyncio.run(load(ws_url, cookies))
    finally:
        forward.terminate()


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("domains", nargs="+", help="sites to copy, e.g. digitec.ch (subdomains included)")
    parser.add_argument("--profile", help="Chrome profile directory (default: the one last used)")
    parser.add_argument("--hosts", action="store_true", help="only list cookie hosts containing the given words")
    parser.add_argument("--context", default="admin@pitower")
    parser.add_argument("--namespace", default="ai")
    args = parser.parse_args()

    profile = args.profile or active_profile()
    store = open_store(profile)

    if args.hosts:
        rows = store.execute("select host_key, count(*) from cookies group by host_key order by host_key")
        for host, count in rows:
            if any(word in host for word in args.domains):
                print(f"{host}\t{count}")
        return

    domains = [d.lower().lstrip(".") for d in args.domains]
    cookies = read_cookies(store, domains)
    if not cookies:
        sys.exit(f"no cookies for {', '.join(domains)} in Chrome profile {profile!r}")
    push([c for _, c in cookies], args.context, args.namespace)
    for domain in domains:
        count = sum(1 for host, _ in cookies if matches(host, [domain]))
        print(f"{domain}: {count} cookies copied")
    print(f"from Chrome profile {profile!r} into hermes")


if __name__ == "__main__":
    main()
