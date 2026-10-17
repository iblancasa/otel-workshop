#!/usr/bin/env bash
# Record terminal sessions for the workshop website, CNCF flavour, then
# convert them to the .txt transcripts the <Terminal> component renders.
#
#   site/src/terminals/common/   commands that look the same in both flavours (shop, kubectl)
#   site/src/terminals/cncf/     commands that talk to Prometheus, Jaeger, Loki
#
# Needs: asciinema >= 3, a running CNCF cluster at step 0 (make prepare).
# Leaves the cluster at step 0 again when done. Takes about 7 minutes.
#
# Usage: ./scripts/record-casts.sh [cast-name ...]   (no args = all)
set -euo pipefail
cd "$(dirname "$0")/.."            # cncf/
ROOT=$(cd .. && pwd)
TERMS=$ROOT/site/src/terminals
mkdir -p "$TERMS/common" "$TERMS/cncf"
export PS1='$ '

# rec <dir> <name> <<'EOF' ... shell lines ... EOF
# Each line is echoed with a prompt, then executed, so the cast reads like a
# real session without typing noise.
rec() {
  local dir=$1 name=$2 script
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
  echo "== recording $dir/$name"
  asciinema rec --overwrite --quiet -f asciicast-v2 -i 2 --window-size 100x24 \
    -c "bash $script" "$TERMS/$dir/$name.cast"
  rm -f "$script"
}

ARGS=("$@")
# w <name>: true when no names were given, or <name> is one of them
w() { [ ${#ARGS[@]} -eq 0 ] || [[ " ${ARGS[*]} " == *" $1 "* ]]; }

# Small helpers the recorded commands call, so the one-liners stay readable.
# They live in scripts/ and are shown on the website next to the output.
export JQ="$ROOT/cncf/scripts/api-helpers.py"

w check && rec cncf check <<'EOF'
make check
EOF

w status && rec cncf status <<'EOF'
make status
make urls
EOF

w checkout && rec common checkout <<'EOF'
curl -s -w ' -> %{time_total}s\n' -X POST localhost:8080/api/checkout -H 'content-type: application/json' -d '{"sku":"US-MUG-02","qty":1}'
curl -s -w ' -> %{time_total}s\n' -X POST localhost:8080/api/checkout -H 'content-type: application/json' -d '{"sku":"EU-HOODIE-03","qty":1}'
EOF

w logs-before && rec common logs-before <<'EOF'
kubectl -n shop logs deploy/frontend --tail=4
kubectl -n shop logs deploy/orders --tail=6
kubectl -n shop logs deploy/inventory --tail=4
EOF

w traffic && rec common traffic <<'EOF'
kubectl -n shop logs deploy/loadgen --tail=10
EOF

w instrument && rec common instrument <<'EOF'
kubectl kustomize ../k8s/apps/instrumented | diff <(kubectl kustomize ../k8s/apps/base) - | grep '^>' | head -12
make instrument
EOF

w logs-after && { sleep 45; rec common logs-after <<'EOF'
kubectl -n shop logs deploy/orders --tail=5 | cut -c1-160
kubectl -n shop logs deploy/frontend --tail=2 | cut -c1-200
kubectl -n shop logs deploy/inventory | grep -m1 javaagent
EOF
}

# Prometheus: the metric names the Collector delivered, then the bimodal buckets.
w promql && { sleep 15; rec cncf promql <<'EOF'
curl -s 'localhost:9090/api/v1/label/__name__/values' | python3 scripts/api-helpers.py names http_
curl -s 'localhost:9090/api/v1/query' --data-urlencode 'query=sum by (le) (http_server_request_duration_seconds_bucket{service_name="frontend",http_route="/api/checkout"})' | python3 scripts/api-helpers.py buckets
EOF
}

# Jaeger: slow traces through the v3 HTTP API (same data the UI shows).
w jaeger-api && rec cncf jaeger-api <<'EOF'
curl -s -G localhost:16686/api/v3/trace-summaries --data-urlencode 'query.service_name=frontend' --data-urlencode 'query.operation_name=POST /api/checkout' --data-urlencode 'query.duration_min=5s' --data-urlencode "query.start_time_min=$(date -u -v-30M +%Y-%m-%dT%H:%M:%SZ)" --data-urlencode "query.start_time_max=$(date -u +%Y-%m-%dT%H:%M:%SZ)" --data-urlencode 'query.search_depth=5' | python3 scripts/api-helpers.py summaries
EOF

# Loki: every log line of one slow trace, via LogQL on structured metadata.
w logql && rec cncf logql <<'EOF'
TID=$(curl -s -G localhost:16686/api/v3/trace-summaries --data-urlencode 'query.service_name=frontend' --data-urlencode 'query.operation_name=POST /api/checkout' --data-urlencode 'query.duration_min=5s' --data-urlencode "query.start_time_min=$(date -u -v-30M +%Y-%m-%dT%H:%M:%SZ)" --data-urlencode "query.start_time_max=$(date -u +%Y-%m-%dT%H:%M:%SZ)" --data-urlencode 'query.search_depth=1' | python3 scripts/api-helpers.py first-trace-id)
curl -s -G localhost:3100/loki/api/v1/query_range --data-urlencode "query={service_name=~\".+\"} | trace_id=\"$TID\"" --data-urlencode since=1h --data-urlencode direction=forward | python3 scripts/api-helpers.py loglines
EOF

w rebuild && {
  ORIG=$(mktemp); cp "$ROOT/services/orders/warehouse.py" "$ORIG"
  cp "$ROOT/solutions/orders/warehouse.py" "$ROOT/services/orders/warehouse.py"
  rec common rebuild <<'EOF'
grep -n 'start_as_current_span\|set_status\|record_exception' ../services/orders/warehouse.py
BUILDKIT_PROGRESS=plain make rebuild-orders 2>&1 | grep -E '^(#[0-9]+ (DONE|naming)|->|loaded|deployment)' | cut -c1-110
EOF
  cp "$ORIG" "$ROOT/services/orders/warehouse.py" && rm -f "$ORIG"
}

# Jaeger: the spans of one slow trace after step 4 (service, ms, status, name).
w jaeger-spans && { sleep 20; rec cncf jaeger-spans <<'EOF'
TID=$(curl -s -G localhost:16686/api/v3/trace-summaries --data-urlencode 'query.service_name=orders' --data-urlencode 'query.operation_name=POST /orders' --data-urlencode 'query.duration_min=5s' --data-urlencode "query.start_time_min=$(date -u -v-30M +%Y-%m-%dT%H:%M:%SZ)" --data-urlencode "query.start_time_max=$(date -u +%Y-%m-%dT%H:%M:%SZ)" --data-urlencode 'query.search_depth=1' | python3 scripts/api-helpers.py first-trace-id)
curl -s "localhost:16686/api/v3/traces/$TID" | python3 scripts/api-helpers.py spans
EOF
}

w fix && rec common fix <<'EOF'
make fix
curl -s -w ' -> %{time_total}s\n' -X POST localhost:8080/api/checkout -H 'content-type: application/json' -d '{"sku":"EU-HOODIE-03","qty":1}'
EOF

w fix && { sleep 10; rec common logs-fixed <<'EOF'
kubectl -n shop logs deploy/orders --tail=30 | grep -E 'WARNING|ERROR' | tail -3 | cut -c1-180
EOF
}

# Service graph edges straight from Prometheus.
w service-graph && rec cncf service-graph <<'EOF'
curl -s localhost:9090/api/v1/query --data-urlencode 'query=sum by (client, server) (rate(traces_service_graph_request_total[5m]))' | python3 scripts/api-helpers.py edges
EOF

# back to step 0
if [ ${#ARGS[@]} -eq 0 ]; then
  make reset >/dev/null 2>&1 && make rebuild-orders >/dev/null 2>&1 || true
fi
python3 "$ROOT/scripts/casts-to-text.py"
ls "$TERMS"/common "$TERMS"/cncf
