#!/usr/bin/env bash
# Verify the tools needed for the workshop.
# Usage: check-tools.sh [host-port ...]   (ports the kind config maps; warns if taken)
set -u
PORTS=("$@")
[ ${#PORTS[@]} -eq 0 ] && PORTS=(8080)
ok=1
need() {
  if command -v "$1" >/dev/null 2>&1; then
    printf "  [ok]   %-8s %s\n" "$1" "$($2 2>/dev/null | head -1)"
  else
    printf "  [MISS] %-8s %s\n" "$1" "$3"; ok=0
  fi
}
echo "Checking tools..."
need docker  "docker version --format {{.Server.Version}}" "https://docs.docker.com/get-docker/ (or colima / podman with docker CLI)"
need kind    "kind version"                                 "https://kind.sigs.k8s.io/docs/user/quick-start/#installation"
need kubectl "kubectl version --client"                     "https://kubernetes.io/docs/tasks/tools/"

if ! docker info >/dev/null 2>&1; then
  echo "  [MISS] docker daemon is not running"; ok=0
fi

if command -v kind >/dev/null 2>&1; then
  v=$(kind version | sed -E 's/.*v0\.([0-9]+)\..*/\1/')
  if [ "${v:-0}" -lt 27 ]; then
    echo "  [WARN] kind >= 0.27 recommended (found $(kind version))"
  fi
fi

for p in "${PORTS[@]}"; do
  if lsof -iTCP:$p -sTCP:LISTEN >/dev/null 2>&1; then
    echo "  [WARN] port $p is in use on this host. Use 'make port-forward' later, or free the port."
  fi
done

[ $ok -eq 1 ] && echo "All good." || { echo "Install the missing tools and run 'make check' again."; exit 1; }
