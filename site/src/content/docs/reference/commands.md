---
title: Commands
description: Every make target in the repository, grouped by when you need it.
---

Run `make help` in the repository for the same list.

## Setup

| Command | What it does |
|---------|--------------|
| `make check` | Verify docker, kind, kubectl, and that ports 3000 and 8080 are free |
| `make prepare` | Everything: check, pull, build, cluster, deploy. Run before the event |
| `make up` | Cluster + deploy from already built images. No network |
| `make down` | Delete the cluster. Images stay cached |
| `make clean` | Delete the cluster and the workshop images |
| `make urls` | Print the two URLs |
| `make status` | Pods in `shop` and `observability` |
| `make port-forward` | Fallback if host ports 3000 or 8080 are taken |

## Workshop steps

| Command | Step | What it does |
|---------|------|--------------|
| `make instrument` | 2 | Apply the instrumented overlay (env vars only), wait for rollout |
| `make uninstrument` | | Back to the plain deployments |
| `make rebuild-orders` | 4 | Rebuild the orders image after editing `services/orders/`, load into kind, restart |
| `make rebuild-frontend`, `make rebuild-inventory` | | Same for the other services |
| `make fix` | 5 | `WAREHOUSE_TIMEOUT_MS=250 WAREHOUSE_RETRIES=1` on the orders deployment |
| `make unfix` | | `2500` / `3` again |
| `make reset` | | Step 0 again: uninstrumented, broken, otelite wiped |

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
| `make logs-frontend`, `logs-orders`, `logs-inventory`, `logs-loadgen` | Tail one service |
| `make shell-frontend`, `shell-orders`, `shell-inventory` | Shell into one service |
| `make collector-logs` | Tail the Collector |

## Offline and website

| Command | What it does |
|---------|--------------|
| `make bundle` | Save all images to `bundle/workshop-images-<arch>.tar` |
| `make image-otelite OTELITE_SRC=../otelite` | Build otelite from a local checkout instead of pulling the GHCR image |
| `make bundle ARCH=amd64` | Cross-build and bundle for the other CPU |
| `make load-bundle BUNDLE=...` | Load a bundle into Docker, then `make up` |
| `make site` | Run this website locally (`site/`, Astro dev server) |
| `make site-build` | Build the static site into `site/dist/` |
| `make casts` | Re-record the terminal transcripts against a running cluster |

## Ports and names

| Thing | Value |
|-------|-------|
| kind cluster | `otel-workshop` (`kubectl --context kind-otel-workshop`) |
| Shop | http://localhost:8080 (NodePort 30080) |
| otelite | http://localhost:3000 (NodePort 30000) |
| OTLP inside the cluster | `otel-collector.observability.svc.cluster.local:4318` (HTTP), `:4317` (gRPC) |
| Namespaces | `shop`, `observability` |
| SKUs | `US-TSHIRT-01`, `US-MUG-02` (fast), `EU-HOODIE-03`, `EU-POSTER-04` (slow) |
