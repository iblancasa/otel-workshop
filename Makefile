# The mystery of the slow API - workshop environment
#
#   make prepare     everything heavy (pull, build, cluster, deploy). Run before the talk.
#   make help        list targets
#
# Offline attendees: make load-bundle BUNDLE=path/to/workshop-images-<arch>.tar && make prepare

SHELL := /bin/bash
.DEFAULT_GOAL := help

CLUSTER        ?= otel-workshop
KIND_NODE_IMAGE ?= kindest/node:v1.32.2
# kind docs recommend pulling node images by digest. We pull by digest and tag
# locally, so the image also has a plain tag inside offline bundles.
KIND_NODE_DIGEST ?= sha256:f226345927d7e348497136874b6d207e0b32cc52154ad8323129352923a3142f
COLLECTOR_IMAGE ?= otel/opentelemetry-collector-contrib:0.161.0
# otelite: the workshop uses a fork with a Service Graph tab, published from
# https://github.com/iblancasa/otelite (branch feat/service-graph) by its
# container-image workflow. Override OTELITE_IMAGE to use something else, or
# OTELITE_SRC=../otelite to build from a local checkout.
OTELITE_IMAGE   ?= ghcr.io/iblancasa/otelite:feat-service-graph
OTELITE_SRC     ?=
APP_IMAGES      := workshop/frontend:latest workshop/orders:latest workshop/inventory:latest workshop/payments:latest workshop/loadgen:latest
ALL_IMAGES      := $(KIND_NODE_IMAGE) $(COLLECTOR_IMAGE) $(OTELITE_IMAGE) $(APP_IMAGES)
KUBECTL         := kubectl --context kind-$(CLUSTER)
ARCH            ?= $(shell uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')
PLATFORM        := linux/$(ARCH)
BUNDLE          ?= bundle/workshop-images-$(ARCH).tar

.PHONY: help check prepare pull images image-otelite image-frontend image-orders image-inventory image-loadgen \
        cluster load deploy-stack deploy-apps up status urls instrument uninstrument \
        rebuild-% fix unfix traffic-off traffic-on traffic-heavy traffic-logs reset down clean bundle load-bundle site site-build casts casts-text logs-% shell-% port-forward

help: ## Show this help
	@grep -E '^[a-zA-Z_%-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

check: ## Verify required tools (docker, kind, kubectl)
	@./scripts/check-tools.sh

# ----------------------------------------------------------------------------
# Heavy lifting: run this while the speaker talks
# ----------------------------------------------------------------------------
prepare: check pull images cluster load deploy-stack deploy-apps urls ## Pull, build, create cluster, deploy everything
	@echo
	@echo "Ready. Open http://localhost:8080 (shop) and http://localhost:3000 (otelite)."

pull: ## Pull third-party images (kind node, collector, otelite)
	docker pull --platform $(PLATFORM) $(KIND_NODE_IMAGE)@$(KIND_NODE_DIGEST)
	docker tag $(KIND_NODE_IMAGE)@$(KIND_NODE_DIGEST) $(KIND_NODE_IMAGE)
	docker pull --platform $(PLATFORM) $(COLLECTOR_IMAGE)
ifeq ($(OTELITE_SRC),)
	docker pull --platform $(PLATFORM) $(OTELITE_IMAGE)
endif

images: image-otelite image-frontend image-orders image-inventory image-payments image-loadgen ## Build all workshop images

image-otelite: ## otelite: pulled from GHCR by default; OTELITE_SRC=../otelite builds it from a local checkout
ifeq ($(OTELITE_SRC),)
	@echo "otelite: using $(OTELITE_IMAGE) (set OTELITE_SRC=path to build from source)"
else
	docker build --platform $(PLATFORM) -f images/otelite/Dockerfile.source -t $(OTELITE_IMAGE) $(OTELITE_SRC)
endif

image-otelite-release: ## otelite from the upstream release binary (no Service Graph tab)
	docker build --platform $(PLATFORM) --build-arg OTELITE_VERSION=v0.1.153 -t $(OTELITE_IMAGE) images/otelite
image-frontend:
	docker build --platform $(PLATFORM) -t workshop/frontend:latest services/frontend
image-orders:
	docker build --platform $(PLATFORM) -t workshop/orders:latest services/orders
image-inventory:
	docker build --platform $(PLATFORM) -t workshop/inventory:latest services/inventory
image-payments:
	docker build --platform $(PLATFORM) -t workshop/payments:latest services/payments
image-loadgen:
	docker build --platform $(PLATFORM) -t workshop/loadgen:latest services/loadgen

cluster: ## Create the kind cluster (idempotent)
	@kind get clusters 2>/dev/null | grep -qx $(CLUSTER) || kind create cluster --config kind/kind.yaml --image $(KIND_NODE_IMAGE)

load: ## Load local images into the kind cluster
	@./scripts/kind-load.sh $(CLUSTER) $(ARCH) $(COLLECTOR_IMAGE) $(OTELITE_IMAGE) $(APP_IMAGES)

deploy-stack: ## Deploy otelite + OpenTelemetry Collector
	$(KUBECTL) apply -f k8s/stack/
	$(KUBECTL) -n observability rollout status deploy/otelite --timeout=120s
	$(KUBECTL) -n observability rollout status deploy/otel-collector --timeout=120s

deploy-apps: ## Deploy the shop WITHOUT instrumentation
	$(KUBECTL) apply -k k8s/apps/base
	$(KUBECTL) -n shop rollout status deploy --timeout=180s

up: cluster load deploy-stack deploy-apps urls ## Cluster + deploy (images must already be built)

# ----------------------------------------------------------------------------
# Workshop steps
# ----------------------------------------------------------------------------
instrument: ## Step 2: enable auto-instrumentation (env vars only)
	$(KUBECTL) apply -k k8s/apps/instrumented
	$(KUBECTL) -n shop rollout status deploy --timeout=180s

uninstrument: ## Go back to the un-instrumented deployments
	$(KUBECTL) apply -k k8s/apps/base
	$(KUBECTL) -n shop rollout status deploy --timeout=180s

rebuild-%: image-% ## Rebuild one service after editing it: make rebuild-frontend | rebuild-orders | rebuild-inventory (step 4 uses orders)
	@./scripts/kind-load.sh $(CLUSTER) $(ARCH) workshop/$*:latest
	$(KUBECTL) -n shop rollout restart deploy/$*
	$(KUBECTL) -n shop rollout status deploy/$* --timeout=120s

fix: ## Step 5: fail fast on the dead warehouse (short timeout, one attempt)
	$(KUBECTL) -n shop set env deploy/orders WAREHOUSE_TIMEOUT_MS=250 WAREHOUSE_RETRIES=1
	$(KUBECTL) -n shop rollout status deploy/orders --timeout=120s

unfix: ## Bring the problem back
	$(KUBECTL) -n shop set env deploy/orders WAREHOUSE_TIMEOUT_MS=2500 WAREHOUSE_RETRIES=3
	$(KUBECTL) -n shop rollout status deploy/orders --timeout=120s

reset: ## Back to the start of the workshop (uninstrumented, broken, fresh otelite data)
	$(KUBECTL) apply -k k8s/apps/base
	$(KUBECTL) -n shop set env deploy/orders WAREHOUSE_TIMEOUT_MS=2500 WAREHOUSE_RETRIES=3
	$(KUBECTL) -n observability rollout restart deploy/otelite
	# the service_graph connector keeps cumulative counters in memory; restart to forget them
	$(KUBECTL) -n observability rollout restart deploy/otel-collector
	$(KUBECTL) -n shop rollout status deploy --timeout=180s
	$(KUBECTL) -n observability rollout status deploy --timeout=120s

# ----------------------------------------------------------------------------
# Background traffic (loadgen is deployed by deploy-apps, 3 workers, 25% EU)
# ----------------------------------------------------------------------------
traffic-off: ## Stop background traffic
	$(KUBECTL) -n shop scale deploy/loadgen --replicas=0

traffic-on: ## Normal background traffic (default)
	$(KUBECTL) -n shop scale deploy/loadgen --replicas=1
	$(KUBECTL) -n shop set env deploy/loadgen WORKERS=3 EU_RATIO=0.25

traffic-heavy: ## 10 workers, half of them EU. Dashboards move fast.
	$(KUBECTL) -n shop scale deploy/loadgen --replicas=1
	$(KUBECTL) -n shop set env deploy/loadgen WORKERS=10 EU_RATIO=0.5

traffic-logs: ## Watch what the load generator gets back (sku -> status in ms)
	$(KUBECTL) -n shop logs deploy/loadgen -f --tail=20

# ----------------------------------------------------------------------------
# Day-to-day
# ----------------------------------------------------------------------------
status: ## Show pods
	@$(KUBECTL) get pods -A -o wide | grep -E "NAMESPACE|shop|observability"

urls: ## Print the URLs
	@echo
	@echo "  Shop     http://localhost:8080"
	@echo "  otelite  http://localhost:3000"
	@echo

SERVICES := frontend orders inventory payments loadgen

logs-%: ## Tail logs of one service: make logs-frontend | logs-orders | logs-inventory | logs-payments | logs-loadgen
	@echo "$(SERVICES)" | grep -qw "$*" || { echo "unknown service '$*'. One of: $(SERVICES)"; exit 1; }
	$(KUBECTL) -n shop logs deploy/$* -f --tail=50

shell-%: ## Shell into one service: make shell-frontend | shell-orders | shell-inventory
	@echo "$(SERVICES)" | grep -qw "$*" || { echo "unknown service '$*'. One of: $(SERVICES)"; exit 1; }
	$(KUBECTL) -n shop exec -it deploy/$* -- sh

collector-logs: ## Tail the collector logs
	$(KUBECTL) -n observability logs deploy/otel-collector -f --tail=50

port-forward: ## Fallback if host ports 3000/8080 are taken
	@echo "otelite -> http://localhost:3000, shop -> http://localhost:8080"
	$(KUBECTL) -n observability port-forward svc/otelite 3000:3000 & \
	$(KUBECTL) -n shop port-forward svc/frontend 8080:3001 & wait

down: ## Delete the kind cluster (keeps images)
	kind delete cluster --name $(CLUSTER)

clean: down ## Delete cluster and workshop images
	-docker rmi $(OTELITE_IMAGE) $(APP_IMAGES)

# ----------------------------------------------------------------------------
# Website (site/, Astro Starlight) and terminal recordings
# ----------------------------------------------------------------------------
site: ## Run the workshop website locally (http://localhost:4321/otel-workshop/)
	cd site && npm install && npm run dev

site-build: ## Build the static website into site/dist/
	cd site && npm install && npm run build

casts: ## Re-record the terminal transcripts (needs a running cluster at step 0, ~6 min)
	@./scripts/record-casts.sh

casts-text: ## Only regenerate the .txt transcripts from existing .cast files
	@python3 scripts/casts-to-text.py

# ----------------------------------------------------------------------------
# Offline mode
# ----------------------------------------------------------------------------
bundle: ## Save every image to bundle/workshop-images-<arch>.tar (speaker, before the event)
	@./scripts/bundle.sh "$(BUNDLE)" $(ALL_IMAGES)

load-bundle: ## Load images from a bundle, then run: make up
	@./scripts/load-bundle.sh "$(BUNDLE)"
