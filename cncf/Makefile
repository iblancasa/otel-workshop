# The mystery of the slow API - CNCF flavour
#
# The same shop, the same Collector, but each signal goes to the tool the
# industry uses for it: traces to Jaeger, metrics to Prometheus, logs to Loki,
# dashboards in Perses. More pods, more memory (6 GB for the Docker VM), more
# tabs to keep open. Also more realistic.
#
#   make prepare     everything heavy (pull, build, cluster, deploy). Run before the talk.
#   make help        list targets
#
# Offline attendees: make load-bundle BUNDLE=path/to/workshop-cncf-images-<arch>.tar && make up

FLAVOUR  := cncf
CLUSTER  ?= otel-workshop-cncf
PORTS    := 8080 3000 9090 16686 3100

# Keep these in sync with the image: lines in k8s/stack/.
JAEGER_IMAGE     ?= jaegertracing/jaeger:2.22.0
PROMETHEUS_IMAGE ?= prom/prometheus:v3.15.0
LOKI_IMAGE       ?= grafana/loki:3.7.8
PERSES_IMAGE     ?= persesdev/perses:v0.54.0
STACK_IMAGES     := $(JAEGER_IMAGE) $(PROMETHEUS_IMAGE) $(LOKI_IMAGE) $(PERSES_IMAGE)

include ../common.mk

STACK_DEPLOYS := jaeger prometheus loki perses otel-collector

deploy-stack: ## Deploy Jaeger, Prometheus, Loki, Perses and the OpenTelemetry Collector
	$(KUBECTL) apply -k k8s/stack
	@for d in $(STACK_DEPLOYS); do $(KUBECTL) -n observability rollout status deploy/$$d --timeout=180s || exit 1; done

reset-stack: ## Wipe traces (Jaeger memory), metrics (Prometheus), logs (Loki) and the Collector's in-memory counters
	$(KUBECTL) -n observability rollout restart deploy/jaeger deploy/prometheus deploy/loki deploy/otel-collector

urls: ## Print the URLs
	@echo
	@echo "  Shop        http://localhost:8080"
	@echo "  Perses      http://localhost:3000        dashboards, log and trace explorer"
	@echo "  Jaeger      http://localhost:16686       traces, Monitor, System Architecture"
	@echo "  Prometheus  http://localhost:9090        PromQL"
	@echo "  Loki        http://localhost:3100        API only (LogQL via Perses or logcli)"
	@echo

port-forward: ## Fallback if host ports are taken
	@echo "perses -> :3000, jaeger -> :16686, prometheus -> :9090, loki -> :3100, shop -> :8080"
	$(KUBECTL) -n observability port-forward svc/perses 3000:8080 & \
	$(KUBECTL) -n observability port-forward svc/jaeger 16686:16686 & \
	$(KUBECTL) -n observability port-forward svc/prometheus 9090:9090 & \
	$(KUBECTL) -n observability port-forward svc/loki 3100:3100 & \
	$(KUBECTL) -n shop port-forward svc/frontend 8080:3001 & wait

stack-logs-%: ## Tail one stack component: make stack-logs-jaeger | stack-logs-prometheus | stack-logs-loki | stack-logs-perses
	$(KUBECTL) -n observability logs deploy/$* -f --tail=50
