"""Payments. Charges a card. Fast, and occasionally says no.

Declines are deterministic so the workshop is reproducible: three posters on
one card trips the per-order limit.
"""
import logging
import time
import uuid

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
log = logging.getLogger("payments")

app = FastAPI(title="payments")

PRICES = {"US-TSHIRT-01": 20, "US-MUG-02": 12, "EU-HOODIE-03": 55, "EU-POSTER-04": 9}
CARD_LIMIT_PER_ORDER = 25  # three posters = 27, declined


class ChargeRequest(BaseModel):
    order_id: str
    sku: str
    qty: int = 1


@app.get("/healthz")
def healthz():
    return {"status": "ok"}


@app.post("/charge")
def charge(req: ChargeRequest):
    amount = PRICES.get(req.sku, 10) * req.qty
    time.sleep(0.03)  # talking to the card network
    if req.sku == "EU-POSTER-04" and amount > CARD_LIMIT_PER_ORDER:
        log.warning("card declined order=%s sku=%s amount=%d limit=%d", req.order_id, req.sku, amount, CARD_LIMIT_PER_ORDER)
        raise HTTPException(status_code=402, detail="card declined: per-order limit")
    log.info("charged order=%s amount=%d", req.order_id, amount)
    return {"payment_id": str(uuid.uuid4())[:8], "amount": amount}
