#!/usr/bin/env bash
# Record terminal sessions for the workshop website (site/src/terminals/*.cast),
# then convert them to the .txt transcripts the <Terminal> component renders.
#
# Needs: asciinema >= 3, a running workshop cluster at step 0 (make prepare).
# Leaves the cluster at step 0 again when done. Takes about 6 minutes.
#
# Usage: ./scripts/record-casts.sh [cast-name ...]   (no args = all)
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=site/src/terminals
mkdir -p "$OUT"
export PS1='$ '

# rec <name> <<'EOF' ... shell lines ... EOF
# Each line is echoed with a prompt, then executed, so the cast reads like a
# real session without typing noise.
rec() {
  local name=$1 script
  script=$(mktemp)
  {
    echo 'set -e'
    while IFS= read -r line; do
      [ -z "$line" ] && { echo 'echo'; continue; }
      printf 'printf "\\033[1;32m$\\033[0m %%s\\n" %q\n' "$line"
      echo "$line"
      echo 'sleep 0.8'
    done
  } > "$script"
  echo "== recording $name"
  asciinema rec --overwrite --quiet -f asciicast-v2 -i 2 --window-size 100x24 \
    -c "bash $script" "$OUT/$name.cast"
  rm -f "$script"
}

ARGS=("$@")
# w <name>: true when no names were given, or <name> is one of them
w() { [ ${#ARGS[@]} -eq 0 ] || [[ " ${ARGS[*]} " == *" $1 "* ]]; }

w check && rec check <<'EOF'
make check
EOF

w status && rec status <<'EOF'
make status
make urls
EOF

w checkout && rec checkout <<'EOF'
curl -s -w ' -> %{time_total}s\n' -X POST localhost:8080/api/checkout -H 'content-type: application/json' -d '{"sku":"US-MUG-02","qty":1}'
curl -s -w ' -> %{time_total}s\n' -X POST localhost:8080/api/checkout -H 'content-type: application/json' -d '{"sku":"EU-HOODIE-03","qty":1}'
EOF

w logs-before && rec logs-before <<'EOF'
kubectl -n shop logs deploy/frontend --tail=4
kubectl -n shop logs deploy/orders --tail=6
kubectl -n shop logs deploy/inventory --tail=4
EOF

w traffic && rec traffic <<'EOF'
kubectl -n shop logs deploy/loadgen --tail=10
EOF

w instrument && rec instrument <<'EOF'
kubectl kustomize k8s/apps/instrumented | diff <(kubectl kustomize k8s/apps/base) - | grep '^>' | head -12
make instrument
EOF

w logs-after && { sleep 45; rec logs-after <<'EOF'
kubectl -n shop logs deploy/orders --tail=5 | cut -c1-160
kubectl -n shop logs deploy/frontend --tail=2 | cut -c1-200
kubectl -n shop logs deploy/inventory | grep -m1 javaagent
EOF
}

w api-traces && { sleep 15; rec api-traces <<'EOF'
curl -s 'localhost:3000/api/traces?limit=200' | python3 -c 'import sys,json; [print(t["trace_id"], t["root_span_name"], t["duration"]//1_000_000, "ms") for t in json.load(sys.stdin)["traces"] if t["duration"] > 5e9][:5]'
EOF
}

w api-logs && rec api-logs <<'EOF'
TID=$(curl -s 'localhost:3000/api/traces?limit=200' | python3 -c 'import sys,json; print([t["trace_id"] for t in json.load(sys.stdin)["traces"] if t["duration"] > 5e9 and t["root_span_name"]=="POST /api/checkout"][0])')
curl -s "localhost:3000/api/logs?trace_id=$TID" | python3 -c 'import sys,json; [print(l["resource"]["attributes"]["service.name"].ljust(9), l["severity"].ljust(5), l["body"][:110]) for l in reversed(json.load(sys.stdin)["logs"])]'
EOF

w rebuild && {
  ORIG=$(mktemp); cp services/orders/warehouse.py "$ORIG"
  cp solutions/orders/warehouse.py services/orders/warehouse.py
  rec rebuild <<'EOF'
grep -n 'start_as_current_span\|set_status\|record_exception' services/orders/warehouse.py
BUILDKIT_PROGRESS=plain make rebuild-orders 2>&1 | grep -E '^(#[0-9]+ (DONE|naming)|->|loaded|deployment)' | cut -c1-110
EOF
  cp "$ORIG" services/orders/warehouse.py && rm -f "$ORIG"
}

w api-spans && { sleep 20; rec api-spans <<'EOF'
TID=$(curl -s 'localhost:3000/api/traces?limit=100' | python3 -c 'import sys,json; print([t["trace_id"] for t in json.load(sys.stdin)["traces"] if t["duration"] > 5e9 and t["has_errors"]][0])')
curl -s "localhost:3000/api/traces/$TID" | python3 -c 'import sys,json; [print(s["attributes"].get("service.name","").ljust(9), str(s["duration"]//1_000_000).rjust(5), "ms", s["status"]["code"].ljust(6), s["name"]) for s in json.load(sys.stdin)["spans"] if not s["name"].startswith("middleware")]'
EOF
}

w fix && rec fix <<'EOF'
make fix
curl -s -w ' -> %{time_total}s\n' -X POST localhost:8080/api/checkout -H 'content-type: application/json' -d '{"sku":"EU-HOODIE-03","qty":1}'
EOF

w fix && { sleep 10; rec logs-fixed <<'EOF'
kubectl -n shop logs deploy/orders --tail=30 | grep -E 'WARNING|ERROR' | tail -3 | cut -c1-180
EOF
}

# back to step 0
if [ ${#ARGS[@]} -eq 0 ]; then
  make reset >/dev/null 2>&1 && make rebuild-orders >/dev/null 2>&1 || true
fi
python3 scripts/casts-to-text.py
ls "$OUT"
