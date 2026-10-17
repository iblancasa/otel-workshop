"""
Legacy warehouse client.

This module talks to the warehouse reservation system through a vendored,
in-house protocol. No OpenTelemetry instrumentation library knows about it,
so auto-instrumentation can NOT see what happens in here. From the outside
it is just "time spent inside the orders service".

The behaviour is simulated so the workshop works without network access.
"""

import logging
import os
import time
from dataclasses import dataclass

log = logging.getLogger("orders.warehouse")

# Configuration. The ops team set these values when the EU warehouse was
# migrated. Nobody has looked at them since.
EU_ENDPOINT = os.getenv("WAREHOUSE_EU_ENDPOINT", "warehouse-eu.internal:9000")
TIMEOUT_MS = int(os.getenv("WAREHOUSE_TIMEOUT_MS", "2500"))
RETRIES = int(os.getenv("WAREHOUSE_RETRIES", "3"))
FALLBACK_MS = 400  # synchronous replica, slow but always answers
LOCAL_MS = 20


class WarehouseTimeout(Exception):
    pass


@dataclass
class Reservation:
    sku: str
    qty: int
    region: str
    mode: str  # "primary" or "fallback"


def region_for(sku: str) -> str:
    prefix = sku.split("-", 1)[0].upper()
    return {"EU": "eu-west", "US": "us-east"}.get(prefix, "us-east")


def _call_primary(region: str, sku: str, qty: int) -> None:
    """Simulated network call. eu-west has been unreachable since the migration."""
    if region == "eu-west":
        time.sleep(TIMEOUT_MS / 1000)
        raise WarehouseTimeout(f"{EU_ENDPOINT} did not answer within {TIMEOUT_MS}ms")
    time.sleep(LOCAL_MS / 1000)


def _call_fallback(region: str, sku: str, qty: int) -> None:
    time.sleep(FALLBACK_MS / 1000)


def reserve(sku: str, qty: int) -> Reservation:
    region = region_for(sku)

    # TODO(workshop step 4): this function is invisible in traces.
    # Wrap it in a span called "warehouse.reserve" and attach
    # warehouse.region, warehouse.sku and warehouse.attempt as attributes.

    attempt = 0
    while True:
        attempt += 1
        try:
            _call_primary(region, sku, qty)
            log.info("reserved %s x%d at %s (attempt %d)", sku, qty, region, attempt)
            return Reservation(sku=sku, qty=qty, region=region, mode="primary")
        except WarehouseTimeout as exc:
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
    _call_fallback(region, sku, qty)
    return Reservation(sku=sku, qty=qty, region=region, mode="fallback")
