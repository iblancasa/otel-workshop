#!/usr/bin/env bash
# Load an offline image bundle into the local docker daemon.
set -euo pipefail
bundle=${1:?usage: load-bundle.sh <bundle.tar>}
[ -f "$bundle" ] || { echo "bundle not found: $bundle"; exit 1; }
echo "Loading $bundle (this takes a minute)..."
docker load -i "$bundle"
echo "Done. Next: make up"
