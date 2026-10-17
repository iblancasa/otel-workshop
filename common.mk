# Shared targets for both flavours of the workshop (otelite/ and cncf/).
#
# A flavour Makefile sets a few variables, includes this file, then defines
# the targets that depend on its observability stack:
#
#   FLAVOUR        otelite | cncf
#   CLUSTER        kind cluster name
#   STACK_IMAGES   third-party images of the stack (pulled, loaded, bundled)
#   PORTS          host ports the kind config maps (checked by `make check`)
#   deploy-stack   apply k8s/stack/ and wait for it
#   reset-stack    wipe the stack's data (restart the stateful pods)
#   urls           print the URLs
#   port-forward   fallback when host ports are taken
#
# Everything that is the same in both flavours lives here: the shop images,
# the kind cluster, the app deployments, the workshop steps, traffic, bundles.

SHELL := /bin/bash
.DEFAULT_GOAL := help

ROOT             := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
KIND_NODE_IMAGE  ?= kindest/node:v1.32.2
# kind docs recommend pulling node images by digest. We pull by digest and tag
# locally, so the image also has a plain tag inside offline bundles.
KIND_NODE_DIGEST ?= sha256:f226345927d7e348497136874b6d207e0b32cc52154ad8323129352923a3142f
COLLECTOR_IMAGE  ?= otel/opentelemetry-collector-contrib:0.161.0
APP_IMAGES       := workshop/frontend:latest workshop/orders:latest workshop/inventory:latest workshop/payments:latest workshop/loadgen:latest
# Images the flavour pulls (STACK_PULL_IMAGES) may differ from the ones it
# loads into kind (STACK_LOAD_IMAGES) when one of them is built locally.
STACK_PULL_IMAGES ?= $(STACK_IMAGES)
STACK_LOAD_IMAGES ?= $(STACK_IMAGES)
ALL_IMAGES       := $(KIND_NODE_IMAGE) $(COLLECTOR_IMAGE) $(STACK_LOAD_IMAGES) $(APP_IMAGES)
KUBECTL          := kubectl --context kind-$(CLUSTER)
ARCH             ?= $(shell uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')
PLATFORM         := linux/$(ARCH)
BUNDLE           ?= bundle/workshop-$(FLAVOUR)-images-$(ARCH).tar
SERVICES         := frontend orders inventory payments loadgen
SCRIPTS          := $(ROOT)/scripts

.PHONY: help check prepare pull images image-frontend image-orders image-inventory image-payments image-loadgen \
        cluster load deploy-stack deploy-apps up status urls instrument uninstrument \
        fix unfix traffic-off traffic-on traffic-heavy traffic-logs reset reset-stack down clean \
        bundle load-bundle site site-build casts casts-text collector-logs port-forward

help: ## Show this help
	@echo "Workshop flavour: $(FLAVOUR)   (cluster $(CLUSTER))"
	@echo
	@grep -hE '^[a-zA-Z_%-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

check: ## Verify required tools (docker, kind, kubectl) and free host ports
	@$(SCRIPTS)/check-tools.sh $(PORTS)

# ----------------------------------------------------------------------------
# Heavy lifting: run this before the event
# ----------------------------------------------------------------------------
prepare: check pull images cluster load deploy-stack deploy-apps urls ## Pull, build, create cluster, deploy everything
	@echo
	@echo "Ready. Open the URLs above."

pull: ## Pull third-party images (kind node, collector, the stack)
	docker pull --platform $(PLATFORM) $(KIND_NODE_IMAGE)@$(KIND_NODE_DIGEST)
	docker tag $(KIND_NODE_IMAGE)@$(KIND_NODE_DIGEST) $(KIND_NODE_IMAGE)
	docker pull --platform $(PLATFORM) $(COLLECTOR_IMAGE)
	@for img in $(STACK_PULL_IMAGES); do docker pull --platform $(PLATFORM) $$img; done

images: image-frontend image-orders image-inventory image-payments image-loadgen $(EXTRA_IMAGE_TARGETS) ## Build the shop images

image-frontend:
	docker build --platform $(PLATFORM) -t workshop/frontend:latest $(ROOT)/services/frontend
image-orders:
	docker build --platform $(PLATFORM) -t workshop/orders:latest $(ROOT)/services/orders
image-inventory:
	docker build --platform $(PLATFORM) -t workshop/inventory:latest $(ROOT)/services/inventory
image-payments:
	docker build --platform $(PLATFORM) -t workshop/payments:latest $(ROOT)/services/payments
image-loadgen:
	docker build --platform $(PLATFORM) -t workshop/loadgen:latest $(ROOT)/services/loadgen

cluster: ## Create the kind cluster (idempotent)
	@kind get clusters 2>/dev/null | grep -qx $(CLUSTER) || kind create cluster --config kind/kind.yaml --image $(KIND_NODE_IMAGE)

load: ## Load local images into the kind cluster
	@$(SCRIPTS)/kind-load.sh $(CLUSTER) $(ARCH) $(COLLECTOR_IMAGE) $(STACK_LOAD_IMAGES) $(APP_IMAGES)

deploy-apps: ## Deploy the shop WITHOUT instrumentation
	$(KUBECTL) apply -k $(ROOT)/k8s/apps/base
	$(KUBECTL) -n shop rollout status deploy --timeout=180s

up: cluster load deploy-stack deploy-apps urls ## Cluster + deploy (images must already be built)

# ----------------------------------------------------------------------------
# Workshop steps
# ----------------------------------------------------------------------------
instrument: ## Step 2: enable auto-instrumentation (env vars only)
	$(KUBECTL) apply -k $(ROOT)/k8s/apps/instrumented
	$(KUBECTL) -n shop rollout status deploy --timeout=180s

uninstrument: ## Go back to the un-instrumented deployments
	$(KUBECTL) apply -k $(ROOT)/k8s/apps/base
	$(KUBECTL) -n shop rollout status deploy --timeout=180s

rebuild-%: image-% ## Rebuild one service after editing it: make rebuild-frontend | rebuild-orders | rebuild-inventory (step 4 uses orders)
	@$(SCRIPTS)/kind-load.sh $(CLUSTER) $(ARCH) workshop/$*:latest
	$(KUBECTL) -n shop rollout restart deploy/$*
	$(KUBECTL) -n shop rollout status deploy/$* --timeout=120s

fix: ## Step 5: fail fast on the dead warehouse (short timeout, one attempt)
	$(KUBECTL) -n shop set env deploy/orders WAREHOUSE_TIMEOUT_MS=250 WAREHOUSE_RETRIES=1
	$(KUBECTL) -n shop rollout status deploy/orders --timeout=120s

unfix: ## Bring the problem back
	$(KUBECTL) -n shop set env deploy/orders WAREHOUSE_TIMEOUT_MS=2500 WAREHOUSE_RETRIES=3
	$(KUBECTL) -n shop rollout status deploy/orders --timeout=120s

reset: ## Back to the start of the workshop (uninstrumented, broken, stack data wiped)
	$(KUBECTL) apply -k $(ROOT)/k8s/apps/base
	$(KUBECTL) -n shop set env deploy/orders WAREHOUSE_TIMEOUT_MS=2500 WAREHOUSE_RETRIES=3
	# shop first: the instrumented pods flush their last spans while they stop.
	# Then wipe the stack, so nothing of the old run survives.
	$(KUBECTL) -n shop rollout status deploy --timeout=180s
	$(MAKE) reset-stack
	$(KUBECTL) -n observability rollout status deploy --timeout=180s

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

logs-%: ## Tail logs of one service: make logs-frontend | logs-orders | logs-inventory | logs-payments | logs-loadgen
	@echo "$(SERVICES)" | grep -qw "$*" || { echo "unknown service '$*'. One of: $(SERVICES)"; exit 1; }
	$(KUBECTL) -n shop logs deploy/$* -f --tail=50

shell-%: ## Shell into one service: make shell-frontend | shell-orders | shell-inventory
	@echo "$(SERVICES)" | grep -qw "$*" || { echo "unknown service '$*'. One of: $(SERVICES)"; exit 1; }
	$(KUBECTL) -n shop exec -it deploy/$* -- sh

collector-logs: ## Tail the Collector logs
	$(KUBECTL) -n observability logs deploy/otel-collector -f --tail=50

down: ## Delete the kind cluster (keeps images)
	kind delete cluster --name $(CLUSTER)

clean: down ## Delete cluster and workshop images
	-docker rmi $(STACK_LOAD_IMAGES) $(APP_IMAGES)

# ----------------------------------------------------------------------------
# Website (site/, Astro Starlight) and terminal recordings
# ----------------------------------------------------------------------------
site: ## Run the workshop website locally (http://localhost:4321/otel-workshop/)
	cd $(ROOT)/site && npm install && npm run dev

site-build: ## Build the static website into site/dist/
	cd $(ROOT)/site && npm install && npm run build

casts: ## Re-record this flavour's terminal transcripts (needs a running cluster at step 0)
	@./scripts/record-casts.sh

casts-text: ## Only regenerate the .txt transcripts from existing .cast files
	@python3 $(SCRIPTS)/casts-to-text.py

# ----------------------------------------------------------------------------
# Offline mode
# ----------------------------------------------------------------------------
bundle: ## Save every image to bundle/workshop-<flavour>-images-<arch>.tar (speaker, before the event)
	@$(SCRIPTS)/bundle.sh "$(BUNDLE)" $(ALL_IMAGES)

load-bundle: ## Load images from a bundle, then run: make up
	@$(SCRIPTS)/load-bundle.sh "$(BUNDLE)"
