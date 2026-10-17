---
title: Commands
description: Every make target of the CNCF flavour, grouped by when you need it. All of them run from the cncf directory.
---

Run `make help` in `cncf/` for the same list. Everything shared with the
otelite flavour (the shop, the steps, traffic, bundles) lives in
`common.mk` at the repository root; the CNCF-specific targets in
`cncf/Makefile`.

## Setup

| Command | What it does |
|---------|--------------|
| `make check` | Verify docker, kind, kubectl, and that ports 8080, 3000, 9090, 16686 and 3100 are free |
| `make prepare` | Everything: check, pull, build, cluster, deploy. Run before the event |
| `make up` | Cluster + deploy from already built images. No network |
| `make down` | Delete the cluster. Images stay cached |
| `make clean` | Delete the cluster and the workshop images |
| `make urls` | Print the five URLs |
| `make status` | Pods in `shop` and `observability` |
| `make port-forward` | Fallback if a host port is taken |

## Workshop steps

| Command | Step | What it does |
|---------|------|--------------|
| `make instrument` | 2 | Apply the instrumented overlay (env vars only), wait for rollout |
| `make uninstrument` | | Back to the plain deployments |
| `make rebuild-orders` | 4 | Rebuild the orders image after editing `services/orders/`, load into kind, restart |
| `make rebuild-frontend`, `make rebuild-inventory` | | Same for the other services |
| `make fix` | 5 | `WAREHOUSE_TIMEOUT_MS=250 WAREHOUSE_RETRIES=1` on the orders deployment |
| `make unfix` | | `2500` / `3` again |
| `make reset` | | Step 0 again: uninstrumented, broken, Jaeger, Prometheus, Loki and the Collector restarted (their data is in memory or in an emptyDir, so it is gone) |

## Traffic

| Command | What it does |
|---------|--------------|
| `make traffic-logs` | Watch the load generator: `sku -> status in ms` |
| `make traffic-on` | Default: 3 workers, 25% EU |
| `make traffic-heavy` | 10 workers, 50% EU |
| `make traffic-off` | Scale the load generator to zero |

## Looking at things

| Command | What it does |
|---------|--------------|
| `make logs-frontend`, `logs-orders`, `logs-inventory`, `logs-payments`, `logs-loadgen` | Tail one service |
| `make shell-frontend`, `shell-orders`, `shell-inventory` | Shell into one service |
| `make collector-logs` | Tail the Collector |
| `make stack-logs-jaeger`, `stack-logs-prometheus`, `stack-logs-loki`, `stack-logs-perses` | Tail one backend |

## Offline and website

| Command | What it does |
|---------|--------------|
| `make bundle` | Save all images to `cncf/bundle/workshop-cncf-images-<arch>.tar` |
| `make bundle ARCH=amd64` | Cross-build and bundle for the other CPU |
| `make load-bundle BUNDLE=...` | Load a bundle into Docker, then `make up` |
| `make site` | Run this website locally (`site/`, Astro dev server) |
| `make site-build` | Build the static site into `site/dist/` |
| `make casts` | Re-record the terminal transcripts against a running cluster |

## Ports and names

| Thing | Value |
|-------|-------|
| kind cluster | `otel-workshop-cncf` (`kubectl --context kind-otel-workshop-cncf`) |
| Shop | http://localhost:8080 (NodePort 30080) |
| Perses | http://localhost:3000 (NodePort 30000, container port 8080) |
| Jaeger UI and API | http://localhost:16686 (NodePort 30686) |
| Prometheus | http://localhost:9090 (NodePort 30090) |
| Loki API | http://localhost:3100 (NodePort 30100) |
| OTLP inside the cluster | `otel-collector.observability.svc.cluster.local:4318` (HTTP), `:4317` (gRPC) |
| Backends inside the cluster | `jaeger:4317` (OTLP), `prometheus:9090/api/v1/otlp`, `loki:3100/otlp`, all in `observability` |
| Namespaces | `shop`, `observability` |
| SKUs | `US-TSHIRT-01`, `US-MUG-02` (fast), `EU-HOODIE-03`, `EU-POSTER-04` (slow) |
| Perses project / dashboard | `workshop` / `slow-api` |

## Editing the stack

Every backend's config is a file in `cncf/k8s/stack/`, turned into a
ConfigMap by [kustomization.yaml](https://github.com/iblancasa/otel-workshop/blob/main/cncf/k8s/stack/kustomization.yaml).
After editing one:

```bash
kubectl apply -k k8s/stack
kubectl -n observability rollout restart deploy/<jaeger|prometheus|loki|perses|otel-collector>
```

The Perses dashboard is re-provisioned from
`k8s/stack/perses/dashboard-slow-api.yaml` on every restart and every hour.
To keep a change you made in the UI, export it first:

```bash
percli login http://localhost:3000
percli get dashboard slow-api -p workshop -o yaml > k8s/stack/perses/dashboard-slow-api.yaml
```
