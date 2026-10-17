---
title: The metrics, explained
description: Every metric the workshop produces, who emits it, what Prometheus calls it, and which ones matter for the investigation.
---

After `make instrument`, Prometheus holds metrics from five sources: the
three language agents, the Collector's two connectors, and the `/metrics`
endpoints it scrapes from the stack itself. This page says what each one
means, and how its OpenTelemetry name turns into the Prometheus name you
type.

## How names change on the way in

The Collector pushes OTLP to Prometheus. With
`translation_strategy: UnderscoreEscapingWithSuffixes` (the default),
Prometheus rewrites every name:

| Rule | OpenTelemetry | Prometheus |
|------|---------------|------------|
| dots become underscores | `http.server.request.duration` | `http_server_request_duration` |
| the unit is appended | unit `s` | `..._seconds` |
| histograms become three series | | `..._seconds_bucket{le}`, `..._seconds_count`, `..._seconds_sum` |
| monotonic counters get `_total` | `traces.span.metrics.calls` | `traces_span_metrics_calls_total` |
| unit `1` on a gauge becomes `_ratio` | `jvm.cpu.recent_utilization` | `jvm_cpu_recent_utilization_ratio` |
| attribute keys too | `http.route` | `http_route` |

Resource attributes are not labels by default. The config promotes
`service.name`, `service.namespace`, `service.instance.id`,
`deployment.environment` and `k8s.pod.name`, so `service_name="orders"`
works in every query. Everything else about the resource lands on one
`target_info` series per service (`telemetry_sdk_language`, and so on).
Reference: [Prometheus and OpenTelemetry](https://prometheus.io/docs/guides/opentelemetry/).

## Three metric types

| Type | What a sample holds | Example |
|------|---------------------|---------|
| counter | a number that only goes up since the process started | `jvm_class_loaded_total` |
| gauge | the current value, can go up or down | `nodejs_eventloop_utilization_ratio` |
| histogram | count, sum, and per-bucket counts of a distribution | `http_server_request_duration_seconds` |

Histograms are the ones to learn. `_count` is how many requests, `_sum /
_count` is the average, and the `_bucket` series tell you the shape: how
many requests took less than 5 ms, less than 10 ms, ... less than 10 s,
cumulatively. `histogram_quantile(0.95, sum by (le) (rate(..._bucket[1m])))`
turns that into a p95. The average of step 3 (about 2 s) hides the story; the
buckets (most under 100 ms, a quarter between 7.5 and 10 s) tell it.

## The ones that matter in this workshop

| Metric | Emitted by | Read it as |
|--------|-----------|------------|
| `http_server_request_duration_seconds_*` | every service (HTTP server hook) | How long this service took to answer, per `service_name`, `http_route` and `http_response_status_code`. **Step 3 starts here.** |
| `http_client_request_duration_seconds_*` | frontend, orders (HTTP client hook) | How long this service waited for the things it called, per `server_address`. Server duration of A minus client duration of A to B is time spent inside A. |
| `traces_span_metrics_calls_total` | Collector, `span_metrics` connector | Spans per `service_name`, `span_name`, `span_kind`, `status_code`. Jaeger's Monitor tab reads it. After step 4, the error rate of `warehouse.reserve` lives here. |
| `traces_span_metrics_duration_milliseconds_*` | connector | Histogram of span duration with the same dimensions. The Monitor tab's latency chart. |
| `traces_service_graph_request_total` | Collector, `service_graph` connector | Requests from `client` to `server`. The dashboard's *Who calls whom* table. |
| `traces_service_graph_request_failed_total` | connector | Of those, how many had an error status on the span. |
| `traces_service_graph_request_server_seconds_*` | connector | Histogram of the edge's latency as seen by the server side. |
| `traces_service_graph_request_client_seconds_*` | connector | Same, as seen by the client side. Client minus server is network plus queueing. |

Everything else below is runtime health. Useful to rule things out ("CPU is
fine"), rarely the first thing you open.

## HTTP (all three languages)

Produced by the HTTP server and client instrumentation in each agent. Stable
semantic conventions ([HTTP metrics spec](https://opentelemetry.io/docs/specs/semconv/http/http-metrics/)),
enabled with `OTEL_SEMCONV_STABILITY_OPT_IN=http`.

| Prometheus name | Type | Labels | Meaning |
|--------|------|------------|---------|
| `http_server_request_duration_seconds` | histogram | `http_request_method`, `http_route`, `http_response_status_code`, `url_scheme`, `network_protocol_version` | Time from first byte of the request to last byte of the response, inside the server. |
| `http_client_request_duration_seconds` | histogram | `http_request_method`, `server_address`, `server_port`, `http_response_status_code` | Time an outgoing call took, as seen by the caller. |
| `http_server_active_requests` | gauge | `http_request_method`, `url_scheme` | Requests in flight right now. Python only in this setup. |
| `http_server_request_body_size_bytes`, `http_server_response_body_size_bytes` | histogram | same as duration | Body bytes. Python only. |

Unlike the otelite flavour, nothing is renamed per service and no route is
dropped: Prometheus keeps one series per label set, which is what a time
series database is for.

## Span metrics (Collector connector)

Produced by the `span_metrics` connector from every span. Configured in
[otel-collector-config.yaml](https://github.com/iblancasa/otel-workshop/blob/main/cncf/k8s/stack/otel-collector-config.yaml)
with `http.request.method`, `http.route` and `http.response.status_code` as
extra dimensions and the buckets `10ms ... 10s`.

| Prometheus name | Type | Labels | Meaning |
|--------|------|------------|---------|
| `traces_span_metrics_calls_total` | counter | `service_name`, `span_name`, `span_kind` (`SPAN_KIND_SERVER`, `_CLIENT`, `_INTERNAL`), `status_code` (`STATUS_CODE_UNSET`, `_OK`, `_ERROR`), `http_*` | Spans seen. Errors are the ones with `status_code="STATUS_CODE_ERROR"`. |
| `traces_span_metrics_duration_milliseconds` | histogram | same | Span duration. |

Jaeger's Monitor tab is PromQL over these, with `normalize_calls` and
`normalize_duration` telling it to expect the `_total` and
`_milliseconds_bucket` suffixes Prometheus added.

## Service graph (Collector connector)

Produced by the `service_graph` connector from pairs of client and server
spans. One series per `(client, server, connection_type)`. Details in
[step 6](/otel-workshop/cncf/steps/06-service-graph/).

| Prometheus name | Type | Labels | Meaning |
|--------|------|------------|---------|
| `traces_service_graph_request_total` | counter | `client`, `server`, `connection_type` | Requests on the edge. |
| `traces_service_graph_request_failed_total` | counter | same | Requests whose server or client span had status `ERROR`. |
| `traces_service_graph_request_server_seconds` | histogram | same | Edge latency, server span duration. |
| `traces_service_graph_request_client_seconds` | histogram | same | Edge latency, client span duration. |
| `traces_service_graph_unpaired_spans_total` | counter | same | Spans that waited `store.ttl` without finding their pair. Non-zero means missing edges. |

`connection_type` is empty for plain HTTP, `virtual_node` when one side was
inferred (the `user` node in front of `frontend`, or a callee that never
answered), `database` or `messaging_system` for those.

## Java runtime (`inventory`, javaagent)

Spec: [JVM metrics semantic conventions](https://opentelemetry.io/docs/specs/semconv/runtime/jvm-metrics/).

| Prometheus name | Type | Labels | Meaning |
|--------|------|------------|---------|
| `jvm_cpu_recent_utilization_ratio` | gauge | | Fraction of CPU the JVM used recently, 0 to 1. This is the "CPU is fine" number. |
| `jvm_cpu_time_seconds_total` | counter | | Total CPU seconds consumed. |
| `jvm_cpu_count` | gauge | | CPUs visible to the JVM. |
| `jvm_memory_used_bytes` | gauge | `jvm_memory_pool_name`, `jvm_memory_type` (heap/non_heap) | Bytes in use per memory pool. |
| `jvm_memory_committed_bytes` | gauge | same | Bytes the OS has actually given the JVM for that pool. |
| `jvm_memory_limit_bytes` | gauge | same | Maximum the pool may grow to (`-Xmx` and friends). |
| `jvm_memory_used_after_last_gc_bytes` | gauge | same | Live data after the last collection. The number that matters for leaks. |
| `jvm_gc_duration_seconds` | histogram | `jvm_gc_name`, `jvm_gc_action` | Garbage collection pauses. Long tail here explains latency spikes. |
| `jvm_thread_count` | gauge | `jvm_thread_state`, `jvm_thread_daemon` | Threads per state. A pile of `blocked` or `waiting` points at a lock or a pool. |
| `jvm_class_count`, `jvm_class_loaded_total`, `jvm_class_unloaded_total` | gauge / counter | | Class loading. Interesting at startup, boring afterwards. |

## Node.js runtime (`frontend`, auto-instrumentations-node)

Source: [`@opentelemetry/instrumentation-runtime-node`](https://github.com/open-telemetry/opentelemetry-js-contrib/tree/main/packages/instrumentation-runtime-node), included in the auto-instrumentations bundle. Spec: [Node.js runtime metrics](https://opentelemetry.io/docs/specs/semconv/runtime/nodejs-metrics/) and [V8 JS engine](https://opentelemetry.io/docs/specs/semconv/runtime/v8js-metrics/).

| Prometheus name | Type | Labels | Meaning |
|--------|------|------------|---------|
| `nodejs_eventloop_utilization_ratio` | gauge | | Fraction of time the event loop was busy. Near 1 means the single thread is saturated and every request queues. Ours sits around 0.01. |
| `nodejs_eventloop_delay_*_seconds` (min, mean, max, p50, p90, p99, stddev) | gauge | | How late the event loop runs its timers. High values mean something synchronous is hogging the thread. The 8 s in this workshop does not show here: the frontend is *waiting* on orders, not computing. |
| `nodejs_eventloop_time_seconds_total` | counter | `nodejs_eventloop_state` (active/idle) | Cumulative time in each state. |
| `v8js_memory_heap_used_bytes` | gauge | `v8js_heap_space_name` | Heap in use per V8 space (new, old, code, ...). |
| `v8js_memory_heap_space_size_bytes`, `..._physical_size_bytes`, `..._available_size_bytes` | gauge | same | Reserved, committed and free bytes per space. |
| `v8js_gc_duration_seconds` | histogram | `v8js_gc_type` (major/minor/incremental) | Garbage collection pauses. |
| `v8js_resource_active` | gauge | `v8js_resource_type` | Handles keeping the process alive: sockets, timers, file descriptors. |

## Python runtime (`orders`, `payments`)

The Python agent exports HTTP metrics but no runtime metrics by default in
this setup. [`opentelemetry-instrumentation-system-metrics`](https://opentelemetry-python-contrib.readthedocs.io/en/latest/instrumentation/system_metrics/system_metrics.html)
adds `process_cpu_*`, `process_memory_*` and `process_runtime_cpython_*` if
you install it; the workshop leaves it out to keep the list short.

## The stack about itself

Prometheus also scrapes, the classic way, four `/metrics` endpoints. Handy
when the pipeline misbehaves:

| Job | Metrics to know |
|-----|-----------------|
| `otel-collector` | `otelcol_receiver_accepted_spans_total`, `otelcol_exporter_sent_spans_total`, `otelcol_exporter_send_failed_metric_points_total`, `otelcol_processor_batch_batch_send_size_*`. If accepted grows and sent does not, an exporter is failing. |
| `jaeger` | `otelcol_receiver_accepted_spans_total` again (Jaeger is a Collector), plus `jaeger_query_requests_total`. |
| `loki` | `loki_distributor_lines_received_total`, `loki_discarded_samples_total` (non-zero means lines rejected, usually structured metadata too large). |
| `perses` | HTTP request counts of the dashboard server. |

## Try it

```bash
# every metric name Prometheus has, filtered
curl -s localhost:9090/api/v1/label/__name__/values | python3 scripts/api-helpers.py names http_

# p95 of the checkout right now
curl -s localhost:9090/api/v1/query --data-urlencode 'query=histogram_quantile(0.95, sum by (le) (rate(http_server_request_duration_seconds_bucket{service_name="frontend",http_route="/api/checkout"}[1m])))'

# the resource attributes Prometheus kept on target_info
curl -s localhost:9090/api/v1/query --data-urlencode 'query=target_info{service_name="inventory"}'

# the raw service graph counters
curl -s localhost:9090/api/v1/query --data-urlencode 'query=sum by (client, server) (rate(traces_service_graph_request_total[5m]))' | python3 scripts/api-helpers.py edges
```
