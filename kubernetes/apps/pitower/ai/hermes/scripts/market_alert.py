#!/usr/bin/env python3
# Reference copy only. Not deployed via kustomize/configMap — live copy is
# kubectl cp'd to /opt/data/scripts/market_alert.py on the hermes PVC, and the
# hourly cron job (id 87938bb115aa, --no-agent --deliver telegram) is
# registered via `hermes cron create`. A fresh PVC needs both steps redone.
import json
import os
import sys
import urllib.request
from datetime import datetime, timezone

STATE_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "market_alert_state.json")

THRESHOLDS = {
    "BTC": 5.0,
    "INTC": 3.0,
}


def fetch_json(url, headers=None):
    req = urllib.request.Request(url, headers=headers or {"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(req, timeout=15) as resp:
        return json.loads(resp.read())


def get_btc():
    data = fetch_json(
        "https://api.coingecko.com/api/v3/simple/price"
        "?ids=bitcoin&vs_currencies=usd&include_24hr_change=true"
    )
    price = data["bitcoin"]["usd"]
    change = data["bitcoin"]["usd_24h_change"]
    return price, change


def get_intc():
    data = fetch_json("https://query1.finance.yahoo.com/v8/finance/chart/INTC")
    meta = data["chart"]["result"][0]["meta"]
    price = meta["regularMarketPrice"]
    prev_close = meta["previousClose"]
    change = (price - prev_close) / prev_close * 100
    return price, change


def load_state():
    try:
        with open(STATE_PATH) as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        return {}


def save_state(state):
    with open(STATE_PATH, "w") as f:
        json.dump(state, f)


def main():
    today = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    state = load_state()
    alerts = []

    checks = []
    try:
        price, change = get_btc()
        checks.append(("BTC", price, change, "$"))
    except Exception as e:
        print(f"market_alert: BTC fetch failed: {e}", file=sys.stderr)

    try:
        price, change = get_intc()
        checks.append(("INTC", price, change, "$"))
    except Exception as e:
        print(f"market_alert: INTC fetch failed: {e}", file=sys.stderr)

    for symbol, price, change, currency in checks:
        threshold = THRESHOLDS[symbol]
        if abs(change) >= threshold and state.get(symbol) != today:
            direction = "up" if change >= 0 else "down"
            arrow = "\U0001F4C8" if change >= 0 else "\U0001F4C9"
            alerts.append(
                f"{arrow} {symbol} is {direction} {abs(change):.1f}% today "
                f"({currency}{price:,.2f})"
            )
            state[symbol] = today

    if alerts:
        save_state(state)
        print("\n".join(alerts))


if __name__ == "__main__":
    main()
