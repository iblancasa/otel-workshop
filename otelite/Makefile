# The mystery of the slow API - otelite flavour
#
# One small backend (otelite) receives everything the OpenTelemetry Collector
# forwards: logs, traces and metrics in one dashboard on http://localhost:3000.
#
#   make prepare     everything heavy (pull, build, cluster, deploy). Run before the talk.
#   make help        list targets
#
# Offline attendees: make load-bundle BUNDLE=path/to/workshop-otelite-images-<arch>.tar && make up

FLAVOUR  := otelite
CLUSTER  ?= otel-workshop
PORTS    := 8080 3000

# otelite: the workshop uses a fork with a Service Graph tab, published from
# https://github.com/iblancasa/otelite (branch feat/service-graph) by its
# container-image workflow. Override OTELITE_IMAGE to use something else, or
# OTELITE_SRC=../../otelite to build from a local checkout.
OTELITE_IMAGE ?= ghcr.io/iblancasa/otelite:feat-service-graph
OTELITE_SRC   ?=

STACK_LOAD_IMAGES := $(OTELITE_IMAGE)
ifeq ($(OTELITE_SRC),)
STACK_PULL_IMAGES := $(OTELITE_IMAGE)
else
STACK_PULL_IMAGES :=
EXTRA_IMAGE_TARGETS := image-otelite
endif

include ../common.mk

.PHONY: image-otelite image-otelite-release

image-otelite: ## otelite: pulled from GHCR by default; OTELITE_SRC=path builds it from a local checkout
ifeq ($(OTELITE_SRC),)
	@echo "otelite: using $(OTELITE_IMAGE) (set OTELITE_SRC=path to build from source)"
else
	docker build --platform $(PLATFORM) -f images/otelite/Dockerfile.source -t $(OTELITE_IMAGE) $(OTELITE_SRC)
endif

image-otelite-release: ## otelite from the upstream release binary (no Service Graph tab)
	docker build --platform $(PLATFORM) --build-arg OTELITE_VERSION=v0.1.153 -t $(OTELITE_IMAGE) images/otelite

deploy-stack: ## Deploy otelite + OpenTelemetry Collector
	$(KUBECTL) apply -f k8s/stack/
	$(KUBECTL) -n observability rollout status deploy/otelite --timeout=120s
	$(KUBECTL) -n observability rollout status deploy/otel-collector --timeout=120s

reset-stack: ## Wipe otelite's data and the Collector's in-memory counters
	$(KUBECTL) -n observability rollout restart deploy/otelite
	# the service_graph connector keeps cumulative counters in memory; restart to forget them
	$(KUBECTL) -n observability rollout restart deploy/otel-collector

urls: ## Print the URLs
	@echo
	@echo "  Shop     http://localhost:8080"
	@echo "  otelite  http://localhost:3000"
	@echo

port-forward: ## Fallback if host ports 3000/8080 are taken
	@echo "otelite -> http://localhost:3000, shop -> http://localhost:8080"
	$(KUBECTL) -n observability port-forward svc/otelite 3000:3000 & \
	$(KUBECTL) -n shop port-forward svc/frontend 8080:3001 & wait
