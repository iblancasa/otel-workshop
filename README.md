# The mystery of the slow API

Hands-on workshop: find a production bottleneck with OpenTelemetry metrics,
traces and logs. Everything runs on your laptop in a [kind](https://kind.sigs.k8s.io/)
cluster, with [otelite](https://github.com/planetf1/otelite) as the backend.

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

 every service  --OTLP-->  OpenTelemetry Collector  --OTLP-->  otelite
```

## Before the workshop

Needs Docker (4 GB for the VM), `kind` >= 0.27, `kubectl`, `make`. Then:

```bash
make prepare      # 5 to 15 minutes on a good network
```

Shop at http://localhost:8080, otelite at http://localhost:3000. Details,
offline bundles and troubleshooting are on the website.

## Commands

```bash
make help            # every target
make status          # pods
make instrument      # step 2: auto-instrumentation via env vars only
make rebuild-orders  # step 4: after editing services/orders/
make fix             # step 5: fail fast on the dead warehouse
make reset           # back to step 0
make traffic-heavy   # more background load (also traffic-on / traffic-off / traffic-logs)
make bundle          # speaker: image tar for USB sticks
make site            # run the website locally
make casts           # re-record the terminal transcripts used on the website
make down            # delete the cluster (images stay cached, `make up` brings it back)
```

## Layout

```
Makefile                  all the commands
kind/kind.yaml            cluster definition (host ports 3000 and 8080)
images/otelite/           Dockerfiles for otelite (release binary, or from source). Default image: ghcr.io/iblancasa/otelite:feat-service-graph, a fork with a Service Graph tab
services/frontend/        Node.js + Express. The button.
services/orders/          Python + FastAPI. Calls inventory and the warehouse. The culprit.
services/inventory/       Java, plain JDK HTTP server. The red herring.
services/payments/        Python + FastAPI. Charges the card, declines a few.
services/loadgen/         Background traffic so the dashboards are never empty.
k8s/stack/                otelite + OpenTelemetry Collector
k8s/apps/base/            the shop, no instrumentation
k8s/apps/instrumented/    kustomize overlay: same shop + OTel env vars
solutions/                solved code for step 4
scripts/                  tool check, kind image loading, bundles, cast recording
site/                     the website (Astro Starlight, Expressive Code)
.github/workflows/        builds site/ and publishes it to GitHub Pages
```

## License

Apache 2.0. otelite is Apache 2.0 by [@planetf1](https://github.com/planetf1).
