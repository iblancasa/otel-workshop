#!/usr/bin/env bash
# Save all workshop images into a single tar for offline distribution.
# Usage: bundle.sh <output.tar> <image> [<image>...]
set -euo pipefail
out=$1; shift
mkdir -p "$(dirname "$out")"
echo "Saving $# images to $out ..."
for img in "$@"; do
  docker image inspect "$img" >/dev/null 2>&1 || { echo "missing image: $img (run make pull images first)"; exit 1; }
done
docker save -o "$out" "$@"
cat > "$(dirname "$out")/README.txt" <<TXT
Workshop image bundle ($(uname -m)), created $(date -u +%Y-%m-%dT%H:%MZ)

  1. Copy the repository and this tar to your laptop.
  2. make load-bundle BUNDLE=$(basename "$out")
  3. make up

Images inside:
$(printf '  %s\n' "$@")
TXT
ls -lh "$out"
