import json
import os
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ROUTER_URL = os.environ["ROUTER_URL"]


def fetch(path):
    with urllib.request.urlopen(ROUTER_URL + path, timeout=10) as resp:
        return resp.read().decode()


def collect():
    models = json.loads(fetch("/models"))["data"]
    lines = []
    for model in (m["id"] for m in models if m["status"]["value"] == "loaded"):
        try:
            # autoload=false: without it the router loads the model to answer,
            # evicting the resident one under --models-max 1.
            body = fetch(f"/metrics?model={model}&autoload=false")
        except urllib.error.HTTPError:
            continue  # unloaded between the two calls
        for line in body.splitlines():
            if line and not line.startswith("#"):
                name, _, value = line.partition(" ")
                line = f'{name}{{model="{model}"}} {value}'
            lines.append(line)
    return "\n".join(lines) + "\n"


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path != "/metrics":
            self.send_error(404)
            return
        body = collect().encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; version=0.0.4")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


ThreadingHTTPServer(("", 9090), Handler).serve_forever()
