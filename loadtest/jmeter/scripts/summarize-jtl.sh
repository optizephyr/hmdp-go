#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 1 ]]; then
  printf 'usage: %s <results.jtl>\n' "$0" >&2
  exit 1
fi

JTL_FILE="$1"
if [[ ! -f "$JTL_FILE" ]]; then
  printf 'jtl file not found: %s\n' "$JTL_FILE" >&2
  exit 1
fi

python3 - "$JTL_FILE" <<'PY'
import csv
import math
import sys

path = sys.argv[1]
elapsed = []
ok = 0
total = 0
timestamps = []

with open(path, newline="", encoding="utf-8") as f:
    reader = csv.DictReader(f)
    for row in reader:
        total += 1
        ts = int(row.get("timeStamp", "0") or 0)
        et = float(row.get("elapsed", "0") or 0)
        succ = (row.get("success", "false") or "false").lower() == "true"
        timestamps.append(ts)
        elapsed.append(et)
        if succ:
            ok += 1

if total == 0:
    print("samples=0")
    sys.exit(0)

elapsed.sort()
timestamps.sort()

def pct(arr, p):
    if not arr:
        return 0.0
    idx = min(len(arr) - 1, math.ceil(p / 100.0 * len(arr)) - 1)
    return arr[idx]

duration_s = max(1e-9, (timestamps[-1] - timestamps[0]) / 1000.0)
qps = total / duration_s
avg = sum(elapsed) / len(elapsed)
p95 = pct(elapsed, 95)
p99 = pct(elapsed, 99)
err_rate = (total - ok) / total

print(f"samples={total}")
print(f"success={ok}")
print(f"error={total-ok}")
print(f"error_rate={err_rate:.4f}")
print(f"qps={qps:.2f}")
print(f"avg_ms={avg:.2f}")
print(f"p95_ms={p95:.2f}")
print(f"p99_ms={p99:.2f}")
PY
