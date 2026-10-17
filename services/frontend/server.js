// Shop frontend. Serves a tiny web page with a "Buy" button and proxies the
// checkout call to the orders service.
//
// Note: there is NOT a single OpenTelemetry line in this file. Instrumentation
// is enabled from the outside via NODE_OPTIONS (see k8s/apps/instrumented).

const express = require("express");
const winston = require("winston");
const path = require("path");

const ORDERS_URL = process.env.ORDERS_URL || "http://orders:8000";
const PORT = process.env.PORT || 3001;

const log = winston.createLogger({
  level: "info",
  format: winston.format.combine(winston.format.timestamp(), winston.format.json()),
  transports: [new winston.transports.Console()],
});

const PRODUCTS = [
  { sku: "US-TSHIRT-01", name: "Conference T-shirt", price: 20 },
  { sku: "US-MUG-02", name: "Observability mug", price: 12 },
  { sku: "EU-HOODIE-03", name: "Trace-me hoodie", price: 55 },
  { sku: "EU-POSTER-04", name: "Span waterfall poster", price: 9 },
];

const app = express();
app.use(express.json());
app.use(express.static(path.join(__dirname, "public")));

app.get("/healthz", (req, res) => res.json({ status: "ok" }));
app.get("/api/products", (req, res) => res.json(PRODUCTS));

app.post("/api/checkout", async (req, res) => {
  const { sku, qty = 1 } = req.body || {};
  const started = Date.now();
  log.info("checkout started", { sku, qty });
  try {
    const upstream = await fetch(`${ORDERS_URL}/orders`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ sku, qty }),
    });
    const body = await upstream.json();
    const ms = Date.now() - started;
    if (!upstream.ok) {
      log.warn("checkout rejected by orders", { sku, status: upstream.status, ms });
      return res.status(upstream.status).json(body);
    }
    if (ms > 3000) {
      log.warn("checkout was slow", { sku, ms });
    }
    log.info("checkout completed", { sku, orderId: body.order_id, ms });
    res.json({ ...body, elapsed_ms: ms });
  } catch (err) {
    log.error("checkout failed", { sku, error: err.message });
    res.status(502).json({ error: "orders service unavailable" });
  }
});

app.listen(PORT, () => log.info(`frontend listening on :${PORT}`));
