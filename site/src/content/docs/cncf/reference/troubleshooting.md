---
title: Troubleshooting
description: Symptoms seen on real laptops and the one-liner that fixes each, for the CNCF flavour.
---

| Symptom | Fix |
|---------|-----|
| `make prepare` fails at `kind create cluster`, or hangs at "Starting control-plane" | Docker VM too small. Docker Desktop: Settings > Resources > Memory >= 6 GB. Colima: `colima start --memory 8`. |
| `address already in use` on 8080, 3000, 9090, 16686 or 3100 | Stop whatever uses it, or `make port-forward` in a second terminal and use the same URLs. The otelite flavour's cluster uses 8080 and 3000 too: `make down` there first. |
| `kind load` prints `content digest ... not found` | Docker's containerd image store and multi-platform images. `scripts/kind-load.sh` saves one platform first; run `make load`. |
| Pods `ImagePullBackOff` | The image is not in the cluster: `make load`. |
| Pods `Pending` forever | Memory. `docker stats`. Close things. The otelite flavour needs 1 GB less. |
| `loki` pod not ready for a minute | Normal. Loki's ingester waits 15 s after joining its ring before it reports ready. |
| Jaeger lists no services after `make instrument` | Wait 30 s (Java is slow to start), reload the page (the Service dropdown is loaded once). Then `make collector-logs`: `connection refused` to `jaeger:4317` means Jaeger restarted, the Collector retries on its own. |
| Prometheus has `up` but no `http_server_*` metrics | Query `otelcol_exporter_send_failed_metric_points_total` on the `otel-collector` job. Non-zero: `make collector-logs` says why, usually Prometheus restarting. Zero: the apps are not instrumented yet, `make instrument`. |
| Prometheus answers `400` to the Collector, Collector logs mention `otlp` | Prometheus started without `--web.enable-otlp-receiver`. Check the args in `k8s/stack/prometheus.yaml`. |
| Loki returns nothing for `{service_name="orders"}` | Check the time range of the Explore page first. Then `loki_discarded_samples_total` in Prometheus (job `loki`): lines rejected, usually structured metadata too large. |
| Perses dashboard says *No data* on every panel | Before step 2 that is correct. After: open Explore, run `up`. If that fails, the Prometheus datasource proxy is broken, `make stack-logs-perses`. |
| Perses lost your dashboard edits | Provisioning re-applies `k8s/stack/perses/*.yaml` every hour and on restart. Export with `percli` first, see [Commands](/otel-workshop/cncf/reference/commands/). |
| Jaeger Monitor tab is empty | It needs the `span_metrics` series in Prometheus: query `traces_span_metrics_calls_total`. Nothing there: the connector is not in the traces pipeline, or the Collector restarted less than 15 s ago (its flush interval). |
| Jaeger System Architecture is empty | It is computed from stored traces. `make reset` or a Jaeger restart wipes memory storage; send traffic for a minute. |
| Only orders logs show up | Normal for the first 30 s after a rollout. |
| Logs appear twice | FastAPI >= 0.14x with its own telemetry on top of the agent. The repo pins 0.115. |
| `make rebuild-orders` fails offline | No build cache on this machine. See [No wifi](/otel-workshop/cncf/reference/offline/). |
| `kubectl top pods` fails | kind has no metrics-server. Not needed, Prometheus has the runtime metrics. |
| Everything is slow | `docker stats`. The Java service, Loki and the kind node take the most. |
| Windows | WSL2 + Docker Desktop WSL integration, run everything inside WSL. Native is untested. |

## Verify the pipeline by hand

```bash
# are the apps instrumented?
kubectl -n shop get deploy orders -o jsonpath='{.spec.template.spec.containers[0].env[*].name}' | tr ' ' '\n' | grep OTEL

# is the collector receiving and forwarding? (its own metrics, scraped by Prometheus)
curl -s localhost:9090/api/v1/query --data-urlencode 'query=sum by (exporter) (otelcol_exporter_sent_spans_total)'
curl -s localhost:9090/api/v1/query --data-urlencode 'query=sum by (exporter) (otelcol_exporter_send_failed_metric_points_total)'
make collector-logs

# does each backend have data?
curl -s localhost:16686/api/v3/services
curl -s localhost:9090/api/v1/label/__name__/values | python3 scripts/api-helpers.py names http_
curl -s localhost:3100/loki/api/v1/labels

# can a pod reach the collector?
kubectl -n shop run probe --rm -i --restart=Never --image=workshop/loadgen:latest --image-pull-policy=IfNotPresent -- \
  python -c 'import urllib.request; print(urllib.request.urlopen(urllib.request.Request("http://otel-collector.observability.svc.cluster.local:4318/v1/traces", data=b"{}", headers={"content-type":"application/json"})).status)'
```

## Start over

```bash
make reset          # step 0 (keeps the cluster)
make down && make up
make clean && make prepare
```
