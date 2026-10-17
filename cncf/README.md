# CNCF flavour

The same shop and the same Collector, but each signal goes to the tool the
industry runs for it:

| signal | tool | host port |
|--------|------|-----------|
| traces | [Jaeger](https://www.jaegertracing.io/) 2.22, in-memory storage | 16686 |
| metrics | [Prometheus](https://prometheus.io/) 3.15, OTLP receiver on | 9090 |
| logs | [Loki](https://grafana.com/oss/loki/) 3.7, single binary, OTLP endpoint | 3100 (API only) |
| dashboards | [Perses](https://perses.dev/) 0.54, dashboard as code | 3000 |

Five pods, 6 GB Docker VM recommended.

```bash
make prepare     # before the event
make help        # every target
```

The workshop pages for this flavour:
https://iblancasa.github.io/otel-workshop/cncf/start/

```
kind/kind.yaml                  cluster otel-workshop-cncf, five host ports
k8s/stack/kustomization.yaml    one ConfigMap per config file below
k8s/stack/otel-collector-config.yaml   no backend-specific processors; span_metrics and
                                service_graph connectors derive metrics from traces
k8s/stack/jaeger-config.yaml    Jaeger v2 (Collector-style config): memory store, Monitor
                                tab reading Prometheus, UI config enabling Monitor + System Architecture
k8s/stack/prometheus-config.yaml  OTLP translation and promoted resource attributes; scrapes the stack
k8s/stack/loki-config.yaml      filesystem storage, structured metadata on
k8s/stack/perses-config.yaml    file database + provisioning folder
k8s/stack/perses/               project, Prometheus and Loki datasources, the slow-api dashboard
scripts/record-casts.sh         re-record the terminal transcripts shown on the website
scripts/api-helpers.py          formatters for the Prometheus, Jaeger v3 and Loki HTTP APIs
```

The shop, its manifests and the shared make targets live one level up.

## Notes

- Perses' Jaeger datasource plugin speaks Jaeger's v1 HTTP API, which
  Jaeger 2.22 no longer serves (`/api/v3` only). Traces are explored in the
  Jaeger UI; the Perses dashboard covers metrics and logs.
- The stack configs were validated offline with the real binaries
  (`otelcol-contrib validate`, `promtool check config`, `loki -verify-config`,
  `percli lint`, and a local run of all five with synthetic OTLP traffic).
  The full kind deployment still needs a run on a laptop with Docker.
