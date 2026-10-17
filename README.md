# The mystery of the slow API

Hands-on workshop: find a production bottleneck with OpenTelemetry metrics,
traces and logs. Everything runs on your laptop in a [kind](https://kind.sigs.k8s.io/)
cluster.

**The workshop itself lives on the website:**
https://iblancasa.github.io/otel-workshop/ (source in [`site/`](site/)).

```
browser / loadgen
      |
      v
 frontend (Node.js)  --->  orders (Python)  --->  inventory (Java)
                             |     |
                             |     '-->  payments (Python)
                             '-->  "warehouse" (legacy client, simulated)

 every service  --OTLP-->  OpenTelemetry Collector  --OTLP-->  the backend(s)
```

## Two flavours

Same shop, same bug, same steps. Only the observability stack differs.
Pick one directory and run everything from there.

| | [`otelite/`](otelite/) | [`cncf/`](cncf/) |
|---|---|---|
| traces | [otelite](https://github.com/planetf1/otelite) | [Jaeger](https://www.jaegertracing.io/) 2 |
| metrics | otelite | [Prometheus](https://prometheus.io/) 3 |
| logs | otelite | [Loki](https://grafana.com/oss/loki/) 3 |
| dashboards | otelite | [Perses](https://perses.dev/) |
| pods in `observability` | 2 | 5 |
| Docker VM | 4 GB | 6 GB |
| kind cluster | `otel-workshop` | `otel-workshop-cncf` |
| host ports | 8080 shop, 3000 otelite | 8080 shop, 3000 Perses, 16686 Jaeger, 9090 Prometheus, 3100 Loki |

Both map the shop to 8080 and the dashboard to 3000, so run one at a time
(`make down` in the other directory).

## Before the workshop

Needs Docker, `kind` >= 0.27, `kubectl`, `make`. Then:

```bash
cd otelite        # or: cd cncf
make prepare      # 5 to 15 minutes on a good network
```

Details, offline bundles and troubleshooting are on the website, per flavour.

## Commands

Every flavour directory has the same targets (shared in [`common.mk`](common.mk)):

```bash
make help            # every target
make status          # pods
make instrument      # step 2: auto-instrumentation via env vars only
make rebuild-orders  # step 4: after editing services/orders/
make fix             # step 5: fail fast on the dead warehouse
make reset           # back to step 0
make traffic-heavy   # more background load (also traffic-on / traffic-off / traffic-logs)
make bundle          # speaker: image tar for USB sticks
make casts           # re-record this flavour's terminal transcripts for the website
make down            # delete the cluster (images stay cached, `make up` brings it back)
```

The website runs from the root: `make site` (dev server) or `make site-build`.

## Layout

```
common.mk                 targets shared by both flavours (shop images, cluster, steps, traffic, bundles)
Makefile                  website only; everything else runs inside a flavour directory
services/frontend/        Node.js + Express. The button.
services/orders/          Python + FastAPI. Calls inventory and the warehouse. The culprit.
services/inventory/       Java, plain JDK HTTP server. The red herring.
services/payments/        Python + FastAPI. Charges the card, declines a few.
services/loadgen/         Background traffic so the dashboards are never empty.
k8s/apps/base/            the shop, no instrumentation
k8s/apps/instrumented/    kustomize overlay: same shop + OTel env vars (identical for both flavours)
solutions/                solved code for step 4
scripts/                  tool check, kind image loading, bundles, cast conversion

otelite/Makefile          flavour: otelite
otelite/kind/kind.yaml    cluster definition (host ports 3000 and 8080)
otelite/k8s/stack/        otelite + OpenTelemetry Collector (with the otelite-specific processors)
otelite/images/otelite/   Dockerfiles for otelite. Default image: ghcr.io/iblancasa/otelite:feat-service-graph, a fork with a Service Graph tab
otelite/scripts/          terminal recording for the website

cncf/Makefile             flavour: CNCF
cncf/kind/kind.yaml       cluster definition (five host ports)
cncf/k8s/stack/           Collector, Jaeger, Prometheus, Loki, Perses; one config file per backend, kustomize turns them into ConfigMaps
cncf/k8s/stack/perses/    Perses project, datasources and the workshop dashboard, provisioned as code
cncf/scripts/             terminal recording, API formatting helpers

site/                     the website (Astro Starlight, Expressive Code), both flavours, switch in the sidebar
.github/workflows/        builds site/ and publishes it to GitHub Pages
```

## License

Apache 2.0. otelite is Apache 2.0 by [@planetf1](https://github.com/planetf1).
