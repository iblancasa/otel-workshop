"""Tiny load generator. Hits the frontend checkout endpoint continuously.

Not instrumented on purpose: traces should start at the frontend, like they
would with a real browser.
"""
import os
import random
import threading
import time
import urllib.request
import json

FRONTEND_URL = os.getenv("FRONTEND_URL", "http://frontend:3001")
WORKERS = int(os.getenv("WORKERS", "3"))
PAUSE_S = float(os.getenv("PAUSE_S", "0.5"))
EU_RATIO = float(os.getenv("EU_RATIO", "0.25"))

US = ["US-TSHIRT-01", "US-MUG-02"]
EU = ["EU-HOODIE-03", "EU-POSTER-04"]


def checkout():
    sku = random.choice(EU) if random.random() < EU_RATIO else random.choice(US)
    body = json.dumps({"sku": sku, "qty": random.randint(1, 3)}).encode()
    req = urllib.request.Request(f"{FRONTEND_URL}/api/checkout", data=body,
                                 headers={"content-type": "application/json"}, method="POST")
    t0 = time.time()
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            status = resp.status
    except Exception as exc:  # noqa: BLE001
        status = getattr(exc, "code", "ERR")
    print(f"{sku} -> {status} in {int((time.time() - t0) * 1000)} ms", flush=True)


def worker():
    while True:
        checkout()
        time.sleep(PAUSE_S + random.random())


if __name__ == "__main__":
    print(f"loadgen: {WORKERS} workers against {FRONTEND_URL}", flush=True)
    threads = [threading.Thread(target=worker, daemon=True) for _ in range(WORKERS)]
    for t in threads:
        t.start()
    while True:
        time.sleep(60)
