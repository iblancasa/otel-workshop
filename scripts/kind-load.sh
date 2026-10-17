#!/usr/bin/env bash
# Load images into the kind cluster.
#
# `kind load docker-image` breaks on multi-platform images when Docker uses the
# containerd image store ("content digest ... not found"). Saving one platform
# to an archive and loading that is reliable everywhere.
#
# Usage: kind-load.sh <cluster> <arch: amd64|arm64> <image> [<image>...]
set -euo pipefail
cluster=$1; arch=$2; shift 2
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
for img in "$@"; do
  echo "-> $img"
  tar="$tmp/img.tar"
  if ! docker save --platform "linux/$arch" -o "$tar" "$img" 2>/dev/null; then
    docker save -o "$tar" "$img"   # older docker without --platform
  fi
  kind load image-archive --name "$cluster" "$tar" >/dev/null
  rm -f "$tar"
done
echo "loaded $# images into kind cluster $cluster"
