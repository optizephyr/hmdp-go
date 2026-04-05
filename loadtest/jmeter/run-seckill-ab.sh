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
AUTH_CHECK_ENABLED="${AUTH_CHECK_ENABLED:-1}"
AUTH_CHECK_PATH="${AUTH_CHECK_PATH:-/user/me}"
AUTH_CHECK_SAMPLES="${AUTH_CHECK_SAMPLES:-3}"
AUTH_CHECK_TIMEOUT_SECONDS="${AUTH_CHECK_TIMEOUT_SECONDS:-5}"
SERVICE_CHECK_ENABLED="${SERVICE_CHECK_ENABLED:-1}"
SERVICE_CHECK_PATH="${SERVICE_CHECK_PATH:-/shop/1}"
SERVICE_CHECK_TIMEOUT_SECONDS="${SERVICE_CHECK_TIMEOUT_SECONDS:-3}"
PROGRESS_INTERVAL_SECONDS="${PROGRESS_INTERVAL_SECONDS:-10}"
RAMP_SECONDS="${RAMP_SECONDS:-20}"
HOLD_SECONDS="${HOLD_SECONDS:-60}"
COOLDOWN_SECONDS="${COOLDOWN_SECONDS:-10}"
CONNECT_TIMEOUT_MS="${CONNECT_TIMEOUT_MS:-2000}"
RESPONSE_TIMEOUT_MS="${RESPONSE_TIMEOUT_MS:-5000}"
AB_MODE="${AB_MODE:-ALL}"
REPORT_ROOT="${REPORT_ROOT:-$REPO_ROOT/loadtest/jmeter/out/seckill}"
MYSQL_HOST="${HMDP_MYSQL_HOST:-127.0.0.1}"
MYSQL_PORT="${HMDP_MYSQL_PORT:-3306}"
MYSQL_USER="${HMDP_MYSQL_USERNAME:-root}"
MYSQL_PASSWORD="${HMDP_MYSQL_PASSWORD:-123456}"
MYSQL_DB="${HMDP_MYSQL_DBNAME:-hmdp}"
REDIS_HOST="${HMDP_REDIS_HOST:-127.0.0.1}"
REDIS_PORT="${HMDP_REDIS_PORT:-6379}"
REDIS_PASSWORD="${HMDP_REDIS_PASSWORD:-}"
REDIS_DB="${HMDP_REDIS_DB:-0}"

if [[ "$TOKEN_CSV" = /* ]]; then
  TOKEN_CSV_PATH="$TOKEN_CSV"
else
  TOKEN_CSV_PATH="$REPO_ROOT/$TOKEN_CSV"
fi

preflight_auth_check() {
  if [[ "$AUTH_CHECK_ENABLED" != "1" ]]; then
    printf '[warn] auth preflight disabled (AUTH_CHECK_ENABLED=%s)\n' "$AUTH_CHECK_ENABLED"
    return 0
  fi

  if ! command -v curl >/dev/null 2>&1; then
    printf 'missing required command: curl\n' >&2
    exit 1
  fi

  if [[ ! -f "$TOKEN_CSV_PATH" ]]; then
    printf 'token csv not found: %s\n' "$TOKEN_CSV_PATH" >&2
    exit 1
  fi

  if [[ ! "$AUTH_CHECK_SAMPLES" =~ ^[0-9]+$ ]] || [[ "$AUTH_CHECK_SAMPLES" -eq 0 ]]; then
    printf 'invalid AUTH_CHECK_SAMPLES: %s\n' "$AUTH_CHECK_SAMPLES" >&2
    exit 1
  fi

  local checked=0
  local http_code
  local auth_url="${BASE_PROTOCOL}://${BASE_HOST}:${BASE_PORT}${AUTH_CHECK_PATH}"

  while IFS=, read -r user_id token; do
    user_id="${user_id//[[:space:]]/}"
    token="${token//[[:space:]]/}"

    if [[ "$user_id" == "userId" ]] || [[ -z "$token" ]]; then
      continue
    fi

    checked=$((checked + 1))
    http_code="$(curl -sS -o /dev/null -m "$AUTH_CHECK_TIMEOUT_SECONDS" -w "%{http_code}" -H "authorization: ${token}" "$auth_url" || true)"

    if [[ "$http_code" != "200" ]]; then
      printf 'auth preflight failed: sample user=%s code=%s url=%s\n' "$user_id" "$http_code" "$auth_url" >&2
      printf 'hint: check BASE_HOST/BASE_PORT, token file freshness, and target environment consistency\n' >&2
      exit 1
    fi

    if [[ "$checked" -ge "$AUTH_CHECK_SAMPLES" ]]; then
      break
    fi
  done <"$TOKEN_CSV_PATH"

  if [[ "$checked" -eq 0 ]]; then
    printf 'no valid token rows found in %s\n' "$TOKEN_CSV_PATH" >&2
    exit 1
  fi

  printf 'auth preflight passed: %s/%s samples against %s\n' "$checked" "$AUTH_CHECK_SAMPLES" "$auth_url"
}

preflight_service_check() {
  if [[ "$SERVICE_CHECK_ENABLED" != "1" ]]; then
    printf '[warn] service preflight disabled (SERVICE_CHECK_ENABLED=%s)\n' "$SERVICE_CHECK_ENABLED"
    return 0
  fi

  if ! command -v curl >/dev/null 2>&1; then
    printf 'missing required command: curl\n' >&2
    exit 1
  fi

  local service_url="${BASE_PROTOCOL}://${BASE_HOST}:${BASE_PORT}${SERVICE_CHECK_PATH}"
  local http_code
  http_code="$(curl -sS -o /dev/null -m "$SERVICE_CHECK_TIMEOUT_SECONDS" -w "%{http_code}" "$service_url" || true)"

  if [[ "$http_code" != "200" ]]; then
    printf 'service preflight failed: code=%s url=%s\n' "$http_code" "$service_url" >&2
    printf 'hint: ensure API is healthy and BASE_HOST/BASE_PORT points to the expected environment\n' >&2
    exit 1
  fi

  printf 'service preflight passed: %s\n' "$service_url"
}

redis_exec() {
  local args=(redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT")
  if [[ -n "$REDIS_PASSWORD" ]]; then
    args+=(-a "$REDIS_PASSWORD")
  fi
  if [[ "$REDIS_DB" != "0" ]]; then
    args+=(-n "$REDIS_DB")
  fi
  "${args[@]}" "$@"
}

parse_non_negative_int() {
  local value="$1"
  if [[ "$value" =~ ^[0-9]+$ ]]; then
    printf '%s' "$value"
    return 0
  fi
  printf '0'
}

run_stage() {
  local scenario="$1"
  local stage_name="$2"
  local users="$3"
  local target_path="$4"

  local out_dir="$REPORT_ROOT/${scenario}/${stage_name}"
  mkdir -p "$out_dir"

  if [[ ! "$PROGRESS_INTERVAL_SECONDS" =~ ^[0-9]+$ ]] || [[ "$PROGRESS_INTERVAL_SECONDS" -eq 0 ]]; then
    printf 'invalid PROGRESS_INTERVAL_SECONDS: %s\n' "$PROGRESS_INTERVAL_SECONDS" >&2
    exit 1
  fi

  progress_printer() {
    local file="$1"
    local label="$2"
    while true; do
      if [[ -f "$file" ]]; then
        local line_count
        line_count="$(wc -l <"$file" | tr -d '[:space:]')"
        if [[ "$line_count" =~ ^[0-9]+$ ]] && [[ "$line_count" -gt 0 ]]; then
          printf '[progress] %s: samples=%s\n' "$label" "$((line_count - 1))"
        else
          printf '[progress] %s: samples=0\n' "$label"
        fi
      else
        printf '[progress] %s: results file not created yet\n' "$label"
      fi
      sleep "$PROGRESS_INTERVAL_SECONDS"
    done
  }

  progress_printer "$out_dir/results.jtl" "${scenario}/${stage_name}" &
  local progress_pid=$!

  cleanup_progress() {
    if kill -0 "$progress_pid" >/dev/null 2>&1; then
      kill "$progress_pid" >/dev/null 2>&1 || true
      wait "$progress_pid" 2>/dev/null || true
    fi
  }
  trap cleanup_progress RETURN

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
    -Jconnect_timeout_ms="$CONNECT_TIMEOUT_MS" \
    -Jresponse_timeout_ms="$RESPONSE_TIMEOUT_MS" \
    -Jtoken_csv="$TOKEN_CSV_PATH"

  cleanup_progress
  trap - RETURN

  "$REPO_ROOT/loadtest/jmeter/scripts/summarize-jtl.sh" "$out_dir/results.jtl" >"$out_dir/summary.txt"
}

reset_stage_baseline() {
  "$REPO_ROOT/loadtest/jmeter/reset/seckill-reset.sh" --voucher-id "$VOUCHER_ID" --stock "$STOCK"
}

run_scenario() {
  local scenario="$1"
  local target_path="$2"

  printf 'Reset baseline for %s stage1_500\n' "$scenario"
  reset_stage_baseline
  run_stage "$scenario" "stage1_500" "500" "$target_path"
  verify_consistency "$REPORT_ROOT/${scenario}/stage1_500/consistency.txt"

  printf 'Reset baseline for %s stage2_1000\n' "$scenario"
  reset_stage_baseline
  run_stage "$scenario" "stage2_1000" "1000" "$target_path"
  verify_consistency "$REPORT_ROOT/${scenario}/stage2_1000/consistency.txt"

  printf 'Reset baseline for %s stage3_2000\n' "$scenario"
  reset_stage_baseline
  run_stage "$scenario" "stage3_2000" "2000" "$target_path"
  verify_consistency "$REPORT_ROOT/${scenario}/stage3_2000/consistency.txt"
}

verify_consistency() {
  local out_file="$1"
  local order_count
  local distinct_user_count
  local redis_stock_key="seckill:stock:${VOUCHER_ID}"
  local redis_order_key="seckill:order:${VOUCHER_ID}"
  local redis_stock_raw
  local redis_order_users_raw
  local redis_stock_value
  local redis_order_user_count

  order_count="$(MYSQL_PWD="$MYSQL_PASSWORD" mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" -D "$MYSQL_DB" -N -s -e "SELECT COUNT(*) FROM tb_voucher_order WHERE voucher_id = ${VOUCHER_ID};")"
  distinct_user_count="$(MYSQL_PWD="$MYSQL_PASSWORD" mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" -D "$MYSQL_DB" -N -s -e "SELECT COUNT(DISTINCT user_id) FROM tb_voucher_order WHERE voucher_id = ${VOUCHER_ID};")"
  redis_stock_raw="$(redis_exec GET "$redis_stock_key" 2>/dev/null || true)"
  redis_order_users_raw="$(redis_exec SCARD "$redis_order_key" 2>/dev/null || true)"
  redis_stock_value="$(parse_non_negative_int "${redis_stock_raw//$'\r'/}")"
  redis_order_user_count="$(parse_non_negative_int "${redis_order_users_raw//$'\r'/}")"

  {
    echo "voucher_id=${VOUCHER_ID}"
    echo "stock=${STOCK}"
    echo "order_count=${order_count}"
    echo "distinct_user_count=${distinct_user_count}"
    echo "duplicate_count=$((order_count - distinct_user_count))"
    echo "expected_remaining_stock=$((STOCK - order_count))"
    echo "redis_stock_key=${redis_stock_key}"
    echo "redis_order_key=${redis_order_key}"
    echo "redis_stock_value=${redis_stock_value}"
    echo "redis_order_user_count=${redis_order_user_count}"
    echo "redis_stock_gap_vs_expected=$((redis_stock_value - (STOCK - order_count)))"
    echo "redis_order_user_gap_vs_db=$((redis_order_user_count - distinct_user_count))"
  } >"$out_file"
}

for cmd in jmeter mysql redis-cli; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    printf 'missing required command: %s\n' "$cmd" >&2
    exit 1
  fi
done

preflight_auth_check
preflight_service_check

AB_MODE="$(printf '%s' "$AB_MODE" | tr '[:lower:]' '[:upper:]')"
if [[ "$AB_MODE" != "ALL" ]] && [[ "$AB_MODE" != "A" ]] && [[ "$AB_MODE" != "B" ]]; then
  printf 'invalid AB_MODE: %s (allowed: ALL|A|B)\n' "$AB_MODE" >&2
  exit 1
fi

mkdir -p "$REPORT_ROOT"

if [[ "$AB_MODE" == "ALL" ]] || [[ "$AB_MODE" == "A" ]]; then
  printf 'Running seckill A baseline (single DB transaction)\n'
  run_scenario "a_tx_baseline" "/voucher-order-abtest/tx/"
fi

if [[ "$AB_MODE" == "ALL" ]] || [[ "$AB_MODE" == "B" ]]; then
  printf 'Running seckill B optimized (Redis+Lua+MQ)\n'
  run_scenario "b_redis_lua_mq" "/voucher-order/seckill/"
fi

printf 'Seckill AB benchmark complete: %s\n' "$REPORT_ROOT"
