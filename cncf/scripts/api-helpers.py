#!/usr/bin/env python3
"""Tiny formatters for the HTTP APIs of Prometheus, Jaeger and Loki.

    curl -s <api> | python3 scripts/api-helpers.py <mode> [arg]

Used by the workshop pages ("terminal people" asides) and by
scripts/record-casts.sh. Modes:

    names [prefix]    Prometheus /api/v1/label/__name__/values: list metric names
    buckets           Prometheus instant query grouped by le: one line per bucket
    edges             Prometheus instant query grouped by client/server: req/s per edge
    summaries         Jaeger /api/v3/trace-summaries: id, root, span count, duration
    first-trace-id    Jaeger /api/v3/trace-summaries: print the first trace id only
    spans             Jaeger /api/v3/traces/<id>: service, duration, status, span name
    loglines          Loki query_range (log lines): service, severity, body
"""
import json
import sys

mode = sys.argv[1] if len(sys.argv) > 1 else "help"
arg = sys.argv[2] if len(sys.argv) > 2 else ""
data = json.load(sys.stdin) if mode != "help" else None


def prom_results(d):
    return d.get("data", {}).get("result", [])


if mode == "names":
    names = [n for n in data["data"] if n.startswith(arg)]
    print(len(data["data"]), "metric names in total,", len(names), "starting with", repr(arg))
    for n in names:
        print(" ", n)

elif mode == "buckets":
    rows = prom_results(data)
    rows.sort(key=lambda r: float(r["metric"]["le"].replace("+Inf", "1e99")))
    for r in rows:
        print("le=" + r["metric"]["le"].rjust(6), str(int(float(r["value"][1]))).rjust(7))

elif mode == "edges":
    for r in prom_results(data):
        m = r["metric"]
        print("%12s -> %-12s %6.2f req/s" % (m.get("client", "?"), m.get("server", "?"), float(r["value"][1])))

elif mode in ("summaries", "first-trace-id"):
    summaries = data.get("summaries", [])
    if mode == "first-trace-id":
        print(summaries[0]["traceId"] if summaries else "")
    else:
        for s in summaries:
            ms = (int(s["maxEndTimeUnixNano"]) - int(s["minStartTimeUnixNano"])) // 1_000_000
            services = ", ".join(sorted(x["name"] for x in s.get("services", [])))
            print(s["traceId"], s.get("rootOperationName", "?"), str(ms).rjust(5), "ms", s.get("spanCount", 0), "spans", "[" + services + "]")

elif mode == "spans":
    for rs in data.get("result", {}).get("resourceSpans", []):
        svc = next((a["value"]["stringValue"] for a in rs["resource"]["attributes"] if a["key"] == "service.name"), "?")
        for ss in rs.get("scopeSpans", []):
            for s in ss.get("spans", []):
                if s["name"].startswith("middleware"):
                    continue
                ms = (int(s["endTimeUnixNano"]) - int(s["startTimeUnixNano"])) // 1_000_000
                status = "ERROR" if s.get("status", {}).get("code") == 2 else "ok"
                print(svc.ljust(9), str(ms).rjust(5), "ms", status.ljust(6), s["name"])

elif mode == "loglines":
    rows = []
    for stream in data.get("data", {}).get("result", []):
        labels = stream["stream"]
        for ts, line in stream["values"]:
            rows.append((int(ts), labels.get("service_name", "?"), labels.get("severity_text", ""), line))
    for _, svc, sev, line in sorted(rows):
        print(svc.ljust(9), sev.ljust(5), line[:110])

else:
    print(__doc__)
