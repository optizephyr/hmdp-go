#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

BASE_PROTOCOL="${BASE_PROTOCOL:-http}"
BASE_HOST="${BASE_HOST:-127.0.0.1}"
BASE_PORT="${BASE_PORT:-8081}"
TOKEN_CSV="${TOKEN_CSV:-loadtest/k6/data/token-users.csv}"
VOUCHER_ID="${VOUCHER_ID:-1}"
STOCK="${STOCK:-200}"
RAMP_SECONDS="${RAMP_SECONDS:-60}"
HOLD_SECONDS="${HOLD_SECONDS:-180}"
COOLDOWN_SECONDS="${COOLDOWN_SECONDS:-30}"
REPORT_ROOT="${REPORT_ROOT:-$REPO_ROOT/loadtest/jmeter/out/seckill}"
MYSQL_HOST="${HMDP_MYSQL_HOST:-127.0.0.1}"
MYSQL_PORT="${HMDP_MYSQL_PORT:-3306}"
MYSQL_USER="${HMDP_MYSQL_USERNAME:-root}"
MYSQL_PASSWORD="${HMDP_MYSQL_PASSWORD:-123456}"
MYSQL_DB="${HMDP_MYSQL_DBNAME:-hmdp}"

run_stage() {
  local scenario="$1"
  local stage_name="$2"
  local users="$3"
  local target_path="$4"

  local out_dir="$REPORT_ROOT/${scenario}/${stage_name}"
  mkdir -p "$out_dir"

  jmeter -n \
    -p "$REPO_ROOT/loadtest/jmeter/user.properties" \
    -t "$REPO_ROOT/loadtest/jmeter/seckill-ab.jmx" \
    -l "$out_dir/results.jtl" \
    -e -o "$out_dir/dashboard" \
    -Jbase_protocol="$BASE_PROTOCOL" \
    -Jbase_host="$BASE_HOST" \
    -Jbase_port="$BASE_PORT" \
    -Jtarget_path="$target_path" \
    -Jvoucher_id="$VOUCHER_ID" \
    -Jusers="$users" \
    -Jramp_up="$RAMP_SECONDS" \
    -Jhold_seconds="$HOLD_SECONDS" \
    -Jcooldown_seconds="$COOLDOWN_SECONDS" \
    -Jtoken_csv="$TOKEN_CSV"

  "$REPO_ROOT/loadtest/jmeter/scripts/summarize-jtl.sh" "$out_dir/results.jtl" >"$out_dir/summary.txt"
}

run_scenario() {
  local scenario="$1"
  local target_path="$2"

  run_stage "$scenario" "stage1_100" "100" "$target_path"
  run_stage "$scenario" "stage2_300" "300" "$target_path"
  run_stage "$scenario" "stage3_800" "800" "$target_path"
}

verify_consistency() {
  local out_file="$1"
  local order_count
  local distinct_user_count

  order_count="$(MYSQL_PWD="$MYSQL_PASSWORD" mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" -D "$MYSQL_DB" -N -s -e "SELECT COUNT(*) FROM tb_voucher_order WHERE voucher_id = ${VOUCHER_ID};")"
  distinct_user_count="$(MYSQL_PWD="$MYSQL_PASSWORD" mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" -D "$MYSQL_DB" -N -s -e "SELECT COUNT(DISTINCT user_id) FROM tb_voucher_order WHERE voucher_id = ${VOUCHER_ID};")"

  {
    echo "voucher_id=${VOUCHER_ID}"
    echo "stock=${STOCK}"
    echo "order_count=${order_count}"
    echo "distinct_user_count=${distinct_user_count}"
    echo "duplicate_count=$((order_count - distinct_user_count))"
    echo "expected_remaining_stock=$((STOCK - order_count))"
  } >"$out_file"
}

for cmd in jmeter mysql; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    printf 'missing required command: %s\n' "$cmd" >&2
    exit 1
  fi
done

mkdir -p "$REPORT_ROOT"

printf 'Running seckill A baseline (single DB transaction)\n'
"$REPO_ROOT/loadtest/jmeter/reset/seckill-reset.sh" --voucher-id "$VOUCHER_ID" --stock "$STOCK"
run_scenario "a_tx_baseline" "/voucher-order-abtest/tx/"
verify_consistency "$REPORT_ROOT/a_tx_baseline/consistency.txt"

printf 'Running seckill B optimized (Redis+Lua+MQ)\n'
"$REPO_ROOT/loadtest/jmeter/reset/seckill-reset.sh" --voucher-id "$VOUCHER_ID" --stock "$STOCK"
run_scenario "b_redis_lua_mq" "/voucher-order/seckill/"
verify_consistency "$REPORT_ROOT/b_redis_lua_mq/consistency.txt"

printf 'Seckill AB benchmark complete: %s\n' "$REPORT_ROOT"
