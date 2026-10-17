import logging
import os
import uuid

import httpx
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

import warehouse

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
log = logging.getLogger("orders")

INVENTORY_URL = os.getenv("INVENTORY_URL", "http://inventory:8081")
PAYMENTS_URL = os.getenv("PAYMENTS_URL", "http://payments:8002")

app = FastAPI(title="orders")
client = httpx.Client(base_url=INVENTORY_URL, timeout=5.0)
payments = httpx.Client(base_url=PAYMENTS_URL, timeout=5.0)


class OrderRequest(BaseModel):
    sku: str
    qty: int = 1


@app.get("/healthz")
def healthz():
    return {"status": "ok"}


@app.post("/orders")
def create_order(req: OrderRequest):
    log.info("new order request sku=%s qty=%d", req.sku, req.qty)

    resp = client.get(f"/stock/{req.sku}")
    if resp.status_code == 404:
        raise HTTPException(status_code=404, detail=f"unknown sku {req.sku}")
    resp.raise_for_status()
    stock = resp.json()

    if stock["available"] < req.qty:
        log.warning("insufficient stock for sku=%s wanted=%d available=%d", req.sku, req.qty, stock["available"])
        raise HTTPException(status_code=409, detail="insufficient stock")

    reservation = warehouse.reserve(req.sku, req.qty)

    order_id = str(uuid.uuid4())[:8]
    pay = payments.post("/charge", json={"order_id": order_id, "sku": req.sku, "qty": req.qty})
    if pay.status_code == 402:
        log.warning("payment declined for order %s: %s", order_id, pay.json().get("detail"))
        raise HTTPException(status_code=402, detail="payment declined")
    pay.raise_for_status()

    log.info("order %s confirmed sku=%s region=%s mode=%s", order_id, req.sku, reservation.region, reservation.mode)
    return {
        "order_id": order_id,
        "sku": req.sku,
        "qty": req.qty,
        "warehouse": {"region": reservation.region, "mode": reservation.mode},
        "payment": pay.json(),
    }
