"""
Legacy warehouse client. SOLVED version for workshop step 4.

Compare with services/orders/warehouse.py. The only additions are:
  - a tracer
  - one span around reserve() with attributes
  - span events for each timeout, record_exception + ERROR status at the end
"""

import logging
import os
import time
from dataclasses import dataclass

from opentelemetry import trace
from opentelemetry.trace import Status, StatusCode

log = logging.getLogger("orders.warehouse")
tracer = trace.get_tracer("orders.warehouse")

EU_ENDPOINT = os.getenv("WAREHOUSE_EU_ENDPOINT", "warehouse-eu.internal:9000")
TIMEOUT_MS = int(os.getenv("WAREHOUSE_TIMEOUT_MS", "2500"))
RETRIES = int(os.getenv("WAREHOUSE_RETRIES", "3"))
FALLBACK_MS = 400
LOCAL_MS = 20


class WarehouseTimeout(Exception):
    pass


@dataclass
class Reservation:
    sku: str
    qty: int
    region: str
    mode: str


def region_for(sku: str) -> str:
    prefix = sku.split("-", 1)[0].upper()
    return {"EU": "eu-west", "US": "us-east"}.get(prefix, "us-east")


def _call_primary(region: str, sku: str, qty: int) -> None:
    if region == "eu-west":
        time.sleep(TIMEOUT_MS / 1000)
        raise WarehouseTimeout(f"{EU_ENDPOINT} did not answer within {TIMEOUT_MS}ms")
    time.sleep(LOCAL_MS / 1000)


def _call_fallback(region: str, sku: str, qty: int) -> None:
    time.sleep(FALLBACK_MS / 1000)


def reserve(sku: str, qty: int) -> Reservation:
    region = region_for(sku)

    with tracer.start_as_current_span("warehouse.reserve") as span:
        span.set_attribute("warehouse.region", region)
        span.set_attribute("warehouse.sku", sku)
        span.set_attribute("warehouse.qty", qty)
        span.set_attribute("warehouse.timeout_ms", TIMEOUT_MS)
        span.set_attribute("warehouse.max_retries", RETRIES)

        attempt = 0
        last_exc: Exception | None = None
        while True:
            attempt += 1
            span.set_attribute("warehouse.attempt", attempt)
            try:
                # Each attempt gets its own child span, so the waterfall shows
                # exactly where the 8 seconds go.
                with tracer.start_as_current_span("warehouse.call_primary") as call:
                    call.set_attribute("warehouse.attempt", attempt)
                    call.set_attribute("net.peer.name", EU_ENDPOINT if region == "eu-west" else "local")
                    _call_primary(region, sku, qty)
                log.info("reserved %s x%d at %s (attempt %d)", sku, qty, region, attempt)
                span.set_attribute("warehouse.mode", "primary")
                return Reservation(sku=sku, qty=qty, region=region, mode="primary")
            except WarehouseTimeout as exc:
                last_exc = exc
                span.add_event("warehouse.timeout", {"attempt": attempt, "timeout_ms": TIMEOUT_MS})
                log.warning(
                    "warehouse reservation timed out after %dms (region=%s sku=%s attempt %d/%d): %s",
                    TIMEOUT_MS, region, sku, attempt, RETRIES, exc,
                )
                if attempt >= RETRIES:
                    break

        log.error(
            "warehouse region %s unreachable after %d attempts, using synchronous replica (slow path) for sku=%s",
            region, RETRIES, sku,
        )
        if last_exc is not None:
            span.record_exception(last_exc)
        span.set_status(Status(StatusCode.ERROR, f"{region} unreachable, used fallback"))
        span.set_attribute("warehouse.mode", "fallback")
        with tracer.start_as_current_span("warehouse.call_fallback"):
            _call_fallback(region, sku, qty)
        return Reservation(sku=sku, qty=qty, region=region, mode="fallback")
