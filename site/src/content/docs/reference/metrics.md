---
title: The metrics, explained
description: Every metric the workshop produces, who emits it, what it measures, and which ones matter for the investigation.
---

After `make instrument`, otelite receives about 45 metric names from four sources: the three language agents, and the Collector's `service_graph` connector. This page says what each one means. Metric names, units and attributes follow the [OpenTelemetry semantic conventions](https://opentelemetry.io/docs/specs/semconv/), which is why a Node.js, a Python and a Java service produce the same `http.server.request.duration` without agreeing on anything.

## Three metric types

| Type | What a sample holds | Example |
|------|---------------------|---------|
| counter | a number that only goes up since the process started | `jvm.class.loaded` |
| gauge | the current value, can go up or down | `nodejs.eventloop.utilization` |
| histogram | count, sum, and per-bucket counts of a distribution | `http.server.request.duration` |

Histograms are the ones to learn. `count` is how many requests, `sum / count` is the average, and the buckets tell you the shape: how many requests took less than 5 ms, less than 10 ms, ... less than 10 s. The average of step 3 (1.9 s) hides the story; the buckets (most under 50 ms, a quarter between 7.5 and 10 s) tell it.

Attributes on a metric split it into series. `http.server.request.duration{http.route="/orders", http.response.status_code=200}` and the same metric with status 402 are two series. Backends let you sum or filter by them. otelite shows one series at a time.

## The ones that matter in this workshop

| Metric | Emitted by | Read it as |
|--------|-----------|------------|
| `http.server.request.duration.<service>` | every service (HTTP server hook) | How long this service took to answer, per route and status code. The suffix is added by our Collector, see below. **Step 3 starts here.** |
| `http.client.request.duration.<service>` | frontend, orders (HTTP client hook) | How long this service waited for the things it called, per `server.address`. Server duration of A minus client duration of A to B is time spent inside A. |
| `traces_service_graph_request_total` | Collector, `service_graph` connector | Requests from `client` to `server`. Cumulative counter per edge. Drawn as arrow width in the Service Graph tab. |
| `traces_service_graph_request_failed_total` | connector | Of those, how many had an error status on the span. Arrow colour. |
| `traces_service_graph_request_server` | connector | Histogram of the edge's latency as seen by the server side. Arrow label. |
| `traces_service_graph_request_client` | connector | Same, as seen by the client side. Client minus server is network plus queueing. |

Everything else below is runtime health. Useful to rule things out ("CPU is fine"), rarely the first thing you open.

## HTTP (all three languages)

Produced by the HTTP server and client instrumentation in each agent. Stable semantic conventions ([HTTP metrics spec](https://opentelemetry.io/docs/specs/semconv/http/http-metrics/)), enabled with `OTEL_SEMCONV_STABILITY_OPT_IN=http`.

| Metric | Type | Unit | Attributes | Meaning |
|--------|------|------|------------|---------|
| `http.server.request.duration` | histogram | s | `http.request.method`, `http.route`, `http.response.status_code`, `url.scheme`, `network.protocol.version` | Time from first byte of the request to last byte of the response, inside the server. |
| `http.client.request.duration` | histogram | s | `http.request.method`, `server.address`, `server.port`, `http.response.status_code` | Time an outgoing call took, as seen by the caller. |
| `http.server.active_requests` | counter (up/down) | `{request}` | `http.request.method`, `url.scheme` | Requests in flight right now. Python only in this setup. |
| `http.server.request.body.size` | histogram | By | same as duration | Request body bytes. Python only. |
| `http.server.response.body.size` | histogram | By | same as duration | Response body bytes. Python only. |

Why the `.frontend` / `.orders` / `.inventory` suffix: otelite keeps one latest data point per metric *name*, across all services. Three services exporting the same name would overwrite each other every five seconds, so our Collector renames the two duration metrics per service with a `transform` processor ([step 1](/otel-workshop/steps/01-stack/)). It also drops `http.server.request.duration` samples for routes nobody will look at (`/`, `/api/products`) with a `filter` processor. In a backend that handles series properly, neither exists and the names are the plain ones above.

## Service graph (Collector connector)

Produced by the `service_graph` connector from pairs of client and server spans. One series per `(client, server, connection_type)`. Cumulative since the Collector started; the Service Graph tab reports the delta inside the window. Details in [step 6](/otel-workshop/steps/06-service-graph/).

| Metric | Type | Unit | Attributes | Meaning |
|--------|------|------|------------|---------|
| `traces_service_graph_request_total` | counter | 1 | `client`, `server`, `connection_type`, `failed` | Requests on the edge. |
| `traces_service_graph_request_failed_total` | counter | 1 | same | Requests whose server or client span had status `ERROR`. |
| `traces_service_graph_request_server` | histogram | s | same | Edge latency, server span duration. |
| `traces_service_graph_request_client` | histogram | s | same | Edge latency, client span duration. |
| `traces_service_graph_unpaired_spans_total` | counter | 1 | same | Spans that waited `store.ttl` without finding their pair. Non-zero means missing edges. Not visible in this setup unless something is wrong. |

`connection_type` is `unset` for plain HTTP, `virtual_node` when one side was inferred (the `user` node in front of `frontend`, or a callee that never answered), `database` or `messaging_system` for those.

## Java runtime (`inventory`, javaagent)

Spec: [JVM metrics semantic conventions](https://opentelemetry.io/docs/specs/semconv/runtime/jvm-metrics/).

| Metric | Type | Unit | Attributes | Meaning |
|--------|------|------|------------|---------|
| `jvm.cpu.recent_utilization` | gauge | 1 | | Fraction of CPU the JVM used recently, 0 to 1. This is the "CPU is fine" number. |
| `jvm.cpu.time` | counter | s | | Total CPU seconds consumed. |
| `jvm.cpu.count` | gauge | `{cpu}` | | CPUs visible to the JVM. |
| `jvm.memory.used` | gauge | By | `jvm.memory.pool.name`, `jvm.memory.type` (heap/non_heap) | Bytes in use per memory pool. |
| `jvm.memory.committed` | gauge | By | same | Bytes the OS has actually given the JVM for that pool. |
| `jvm.memory.limit` | gauge | By | same | Maximum the pool may grow to (`-Xmx` and friends). |
| `jvm.memory.used_after_last_gc` | gauge | By | same | Live data after the last collection. The number that matters for leaks. |
| `jvm.gc.duration` | histogram | s | `jvm.gc.name`, `jvm.gc.action` | Garbage collection pauses. Long tail here explains latency spikes. |
| `jvm.thread.count` | gauge | `{thread}` | `jvm.thread.state`, `jvm.thread.daemon` | Threads per state. A pile of `blocked` or `waiting` points at a lock or a pool. |
| `jvm.class.count`, `jvm.class.loaded`, `jvm.class.unloaded` | gauge / counter | `{class}` | | Class loading. Interesting at startup, boring afterwards. |

The Java agent also reports on itself: `processedSpans`, `processedLogs` (with a `dropped` attribute), `queueSize`, `otlp.exporter.seen` and `otlp.exporter.exported`. If `dropped=true` counts climb, the exporter cannot keep up and you are losing telemetry.

## Node.js runtime (`frontend`, auto-instrumentations-node)

Source: [`@opentelemetry/instrumentation-runtime-node`](https://github.com/open-telemetry/opentelemetry-js-contrib/tree/main/packages/instrumentation-runtime-node), included in the auto-instrumentations bundle. Spec: [Node.js runtime metrics](https://opentelemetry.io/docs/specs/semconv/runtime/nodejs-metrics/) and [V8 JS engine](https://opentelemetry.io/docs/specs/semconv/runtime/v8js-metrics/).

| Metric | Type | Unit | Attributes | Meaning |
|--------|------|------|------------|---------|
| `nodejs.eventloop.utilization` | gauge | 1 | | Fraction of time the event loop was busy. Near 1 means the single thread is saturated and every request queues. Ours sits around 0.01. |
| `nodejs.eventloop.delay.min/mean/max/p50/p90/p99/stddev` | gauge | s | | How late the event loop runs its timers. High values mean something synchronous is hogging the thread. The 8 s in this workshop does not show here: the frontend is *waiting* on orders, not computing. |
| `nodejs.eventloop.time` | counter | s | `nodejs.eventloop.state` (active/idle) | Cumulative time in each state. |
| `v8js.memory.heap.used` | gauge | By | `v8js.heap.space.name` | Heap in use per V8 space (new, old, code, ...). |
| `v8js.memory.heap.space.size`, `.physical_size`, `.available_size` | gauge | By | same | Reserved, committed and free bytes per space. |
| `v8js.gc.duration` | histogram | s | `v8js.gc.type` (major/minor/incremental) | Garbage collection pauses. |
| `v8js.resource.active` | gauge | `{resource}` | `v8js.resource.type` | Handles keeping the process alive: sockets, timers, file descriptors. |

## Python runtime (`orders`, `payments`)

The Python agent exports HTTP metrics but no runtime metrics by default in this setup. [`opentelemetry-instrumentation-system-metrics`](https://opentelemetry-python-contrib.readthedocs.io/en/latest/instrumentation/system_metrics/system_metrics.html) adds `process.cpu.*`, `process.memory.*` and `process.runtime.cpython.*` if you install it; the workshop leaves it out to keep the list short.

## Reading a histogram in otelite

Metrics tab, click a histogram. The headline is `sum / count` (average) and the observation count of the latest sample. The **bucket distribution** bars are the latest sample's per-bucket counts, cumulative since the process started. The line chart below is the average per time bucket. Two consequences:

- After `make fix` the distribution still shows the old 7.5 to 10 s group. It stops growing; it does not shrink. Watch the counts, or restart the pod.
- "Latest sample" is one series. For `http.server.request.duration.frontend` that is `/api/checkout` with status 200, because the Collector filtered the other routes.

## Try it

```bash
# every metric name otelite has seen
curl -s localhost:3000/api/metrics/names | python3 -m json.tool

# latest sample of one metric, with attributes
curl -s 'localhost:3000/api/metrics?name=http.server.request.duration.orders&limit=1' | python3 -m json.tool

# the raw service graph counters
curl -s 'localhost:3000/api/metrics?name=traces_service_graph_request_total&limit=10' \
  | python3 -c 'import sys,json; [print(p["attributes"]["client"], "->", p["attributes"]["server"], p["value"]) for p in json.load(sys.stdin)]'
```
