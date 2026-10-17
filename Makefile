# The mystery of the slow API. Two flavours of the same workshop:
#
#   cd otelite && make prepare    one small backend (otelite). Default. 4 GB Docker VM.
#   cd cncf    && make prepare    Jaeger + Prometheus + Loki + Perses. 6 GB Docker VM.
#
# This root Makefile only runs the website. Everything else lives in the
# flavour directories (shared targets in common.mk).
SHELL := /bin/bash
.DEFAULT_GOAL := help
.PHONY: help site site-build

help: ## Show this help
	@echo "Pick a flavour first:"
	@echo
	@echo "  cd otelite && make prepare     otelite backend (default, lighter)"
	@echo "  cd cncf    && make prepare     Jaeger, Prometheus, Loki, Perses"
	@echo
	@grep -E '^[a-zA-Z_%-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

site: ## Run the workshop website locally (http://localhost:4321/otel-workshop/)
	cd site && npm install && npm run dev

site-build: ## Build the static website into site/dist/
	cd site && npm install && npm run build
