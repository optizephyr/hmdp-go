#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

BASE_PROTOCOL="${BASE_PROTOCOL:-http}"
BASE_HOST="${BASE_HOST:-127.0.0.1}"
BASE_PORT="${BASE_PORT:-8081}"
SHOP_IDS_CSV="${SHOP_IDS_CSV:-loadtest/k6/data/shop-ids.csv}"
RAMP_SECONDS="${RAMP_SECONDS:-60}"
HOLD_SECONDS="${HOLD_SECONDS:-180}"
COOLDOWN_SECONDS="${COOLDOWN_SECONDS:-30}"
REPORT_ROOT="${REPORT_ROOT:-$REPO_ROOT/loadtest/jmeter/out/read}"

run_stage() {
  local scenario="$1"
  local stage_name="$2"
  local users="$3"
  local target_path="$4"

  local out_dir="$REPORT_ROOT/${scenario}/${stage_name}"
  mkdir -p "$out_dir"

  jmeter -n \
    -p "$REPO_ROOT/loadtest/jmeter/user.properties" \
    -t "$REPO_ROOT/loadtest/jmeter/read-ab.jmx" \
    -l "$out_dir/results.jtl" \
    -e -o "$out_dir/dashboard" \
    -Jbase_protocol="$BASE_PROTOCOL" \
    -Jbase_host="$BASE_HOST" \
    -Jbase_port="$BASE_PORT" \
    -Jtarget_path="$target_path" \
    -Jusers="$users" \
    -Jramp_up="$RAMP_SECONDS" \
    -Jhold_seconds="$HOLD_SECONDS" \
    -Jcooldown_seconds="$COOLDOWN_SECONDS" \
    -Jshop_ids_csv="$SHOP_IDS_CSV"

  "$REPO_ROOT/loadtest/jmeter/scripts/summarize-jtl.sh" "$out_dir/results.jtl" >"$out_dir/summary.txt"
}

run_scenario() {
  local scenario="$1"
  local target_path="$2"

  run_stage "$scenario" "stage1_100" "100" "$target_path"
  run_stage "$scenario" "stage2_300" "300" "$target_path"
  run_stage "$scenario" "stage3_600" "600" "$target_path"
}

if ! command -v jmeter >/dev/null 2>&1; then
  printf 'missing required command: jmeter\n' >&2
  exit 1
fi

mkdir -p "$REPORT_ROOT"

printf 'Running read A baseline (direct DB)\n'
"$REPO_ROOT/loadtest/jmeter/reset/read-reset.sh"
run_scenario "a_direct_db" "/shop-abtest/direct-db/"

printf 'Running read B optimized (cache)\n'
"$REPO_ROOT/loadtest/jmeter/reset/read-reset.sh"
run_scenario "b_cache" "/shop/"

printf 'Read AB benchmark complete: %s\n' "$REPORT_ROOT"
