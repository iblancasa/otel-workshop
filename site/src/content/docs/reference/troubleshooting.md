---
title: Troubleshooting
description: Symptoms seen on real laptops and the one-liner that fixes each.
---

| Symptom | Fix |
|---------|-----|
| `make prepare` fails at `kind create cluster`, or hangs at "Starting control-plane" | Docker VM too small. Docker Desktop: Settings > Resources > Memory >= 4 GB. Colima: `colima start --memory 6`. |
| `address already in use` on 3000 or 8080 | Stop whatever uses it, or `make port-forward` in a second terminal and use the same URLs. |
| `kind load` prints `content digest ... not found` | Docker's containerd image store and multi-platform images. `scripts/kind-load.sh` saves one platform first; run `make load`. |
| Pods `ImagePullBackOff` | The image is not in the cluster: `make load`. |
| Pods `Pending` forever | Memory. `docker stats`. Close things. |
| otelite shows nothing after `make instrument` | Wait 30 s (Java is slow to start). Then `make collector-logs`: `Exporting failed` means otelite is restarting. `connection refused` to the collector means the apps rolled before it was ready, `make instrument` again. |
| Only orders logs show up | Normal for the first 30 s after a rollout. |
| Traces list shows a trace with root `GET /stock/` or `POST /orders` | Spans still arriving. Refresh. |
| The Traces or Logs tab stops updating | The time window froze at page load. Tick **Auto-refresh** or **Now** + **Apply**. |
| A metric disappears from the Metrics list | otelite keeps one latest point per metric name; the Collector renames per service to avoid this. If you removed that processor, put it back. |
| Logs appear twice | FastAPI >= 0.14x with its own telemetry on top of the agent. The repo pins 0.115. |
| `make rebuild-orders` fails offline | No build cache on this machine. See [No wifi](/otel-workshop/reference/offline/). |
| `kubectl top pods` fails | kind has no metrics-server. Not needed. |
| Everything is slow | `docker stats`. The Java service and the kind node take the most. |
| Windows | WSL2 + Docker Desktop WSL integration, run everything inside WSL. Native is untested. |

## Verify the pipeline by hand

```bash
# are the apps instrumented?
kubectl -n shop get deploy orders -o jsonpath='{.spec.template.spec.containers[0].env[*].name}' | tr ' ' '\n' | grep OTEL

# is the collector receiving and forwarding?
make collector-logs

# does otelite have data?
curl -s 'localhost:3000/api/traces?limit=1'
curl -s 'localhost:3000/api/metrics/names'

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
