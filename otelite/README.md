# otelite flavour

One small backend. The OpenTelemetry Collector forwards logs, traces and
metrics to [otelite](https://github.com/planetf1/otelite), a single binary
with one dashboard on http://localhost:3000. Two pods, under 100 MB of
memory for the backend, 4 GB Docker VM.

```bash
make prepare     # before the event
make help        # every target
```

The workshop pages for this flavour:
https://iblancasa.github.io/otel-workshop/otelite/start/

```
kind/kind.yaml           cluster otel-workshop, host ports 3000 (otelite) and 8080 (shop)
k8s/stack/               otelite + Collector. The Collector config carries three processors
                         that exist only because of otelite (resource attrs onto spans,
                         per-service metric names, route filter). Read the comments.
images/otelite/          Dockerfiles: release binary, or from a local checkout (OTELITE_SRC=)
scripts/record-casts.sh  re-record the terminal transcripts shown on the website
```

The shop, its manifests and the shared make targets live one level up.
