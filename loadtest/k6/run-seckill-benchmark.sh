#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

MYSQL_HOST="${HMDP_MYSQL_HOST:-127.0.0.1}"
MYSQL_PORT="${HMDP_MYSQL_PORT:-3306}"
MYSQL_USER="${HMDP_MYSQL_USERNAME:-root}"
MYSQL_PASSWORD="${HMDP_MYSQL_PASSWORD:-123456}"
MYSQL_DB="${HMDP_MYSQL_DBNAME:-hmdp}"
REDIS_HOST="${HMDP_REDIS_HOST:-127.0.0.1}"
REDIS_PORT="${HMDP_REDIS_PORT:-6379}"
REDIS_PASSWORD="${HMDP_REDIS_PASSWORD:-}"
REDIS_DB="${HMDP_REDIS_DB:-0}"
BASE_URL="${BASE_URL:-http://127.0.0.1:8081}"
VOUCHER_ID="${K6_VOUCHER_ID:-1}"
K6_QPS="${K6_QPS:-1000}"
K6_STOCK="${K6_STOCK:-200}"
K6_DURATION="${K6_DURATION:-1m}"
K6_TOKEN_COUNT="${K6_TOKEN_COUNT:-1000}"
SKIP_PREPARE="${SKIP_PREPARE:-0}"
SKIP_VERIFY="${SKIP_VERIFY:-0}"
PREPARE_ONLY="${PREPARE_ONLY:-0}"

usage() {
  cat <<'EOF'
Usage: bash loadtest/k6/run-seckill-benchmark.sh [options]

Options:
  --qps <n>            Benchmark arrival rate per second
  --stock <n>          Initial seckill stock
  --duration <value>   Benchmark duration (default: 1m)
  --token-count <n>    Number of generated tokens to use
  --voucher-id <n>     Voucher ID to reset and benchmark
  --base-url <url>     Service base URL for k6 requests
  --skip-prepare       Skip token generation and baseline reset
  --skip-verify        Skip Redis/MySQL post-run verification
  --prepare-only       Run preparation steps and exit before k6
  -h, --help           Show this help text

Remote run example:
  HMDP_MYSQL_HOST=work-ubuntu HMDP_REDIS_HOST=work-ubuntu \
  BASE_URL=http://work-ubuntu:8081 SKIP_PREPARE=1 SKIP_VERIFY=1 \
  bash loadtest/k6/run-seckill-benchmark.sh
EOF
}

require_positive_int() {
  case "$1" in
    ''|*[!0-9]*|0)
      printf 'invalid %s: %s\n' "$2" "$1" >&2
      exit 1
      ;;
  esac
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

while [[ $# -gt 0 ]]; do
  case "$1" in
    --qps)
      K6_QPS="$2"
      shift 2
      ;;
    --qps=*)
      K6_QPS="${1#*=}"
      shift
      ;;
    --stock)
      K6_STOCK="$2"
      shift 2
      ;;
    --stock=*)
      K6_STOCK="${1#*=}"
      shift
      ;;
    --duration)
      K6_DURATION="$2"
      shift 2
      ;;
    --duration=*)
      K6_DURATION="${1#*=}"
      shift
      ;;
    --token-count)
      K6_TOKEN_COUNT="$2"
      shift 2
      ;;
    --token-count=*)
      K6_TOKEN_COUNT="${1#*=}"
      shift
      ;;
    --voucher-id)
      VOUCHER_ID="$2"
      shift 2
      ;;
    --voucher-id=*)
      VOUCHER_ID="${1#*=}"
      shift
      ;;
    --base-url)
      BASE_URL="$2"
      shift 2
      ;;
    --base-url=*)
      BASE_URL="${1#*=}"
      shift
      ;;
    --skip-prepare)
      SKIP_PREPARE=1
      shift
      ;;
    --skip-verify)
      SKIP_VERIFY=1
      shift
      ;;
    --prepare-only)
      PREPARE_ONLY=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'unknown option: %s\n' "$1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

require_positive_int "$K6_QPS" "qps"
require_positive_int "$K6_STOCK" "stock"
require_positive_int "$K6_TOKEN_COUNT" "token-count"
require_positive_int "$VOUCHER_ID" "voucher-id"

required_tools=()
if [[ "$PREPARE_ONLY" -eq 0 ]]; then
  required_tools+=(k6)
fi
if [[ "$SKIP_PREPARE" -eq 0 ]]; then
  required_tools+=(go mysql redis-cli)
elif [[ "$SKIP_VERIFY" -eq 0 || "$PREPARE_ONLY" -ne 0 ]]; then
  required_tools+=(mysql redis-cli)
fi

for tool in "${required_tools[@]}"; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    printf 'missing required command: %s\n' "$tool" >&2
    exit 1
  fi
done

printf '\n=== seckill benchmark: %s qps / %s stock ===\n' "$K6_QPS" "$K6_STOCK"

if [[ "$SKIP_PREPARE" -eq 0 ]]; then
  printf 'preparing token data...\n'

  (
    cd "$REPO_ROOT"
    HMDP_MYSQL_HOST="$MYSQL_HOST" \
      HMDP_MYSQL_PORT="$MYSQL_PORT" \
      HMDP_MYSQL_USERNAME="$MYSQL_USER" \
      HMDP_MYSQL_PASSWORD="$MYSQL_PASSWORD" \
      HMDP_MYSQL_DBNAME="$MYSQL_DB" \
      HMDP_REDIS_HOST="$REDIS_HOST" \
      HMDP_REDIS_PORT="$REDIS_PORT" \
      HMDP_REDIS_PASSWORD="$REDIS_PASSWORD" \
      HMDP_REDIS_DB="$REDIS_DB" \
      K6_TOKEN_COUNT="$K6_TOKEN_COUNT" \
      go test -tags k6data ./internal/test -run TestGenerate1000Tokens -v
  )

  printf 'resetting mysql baseline...\n'
  MYSQL_PWD="$MYSQL_PASSWORD" mysql \
    -h "$MYSQL_HOST" \
    -P "$MYSQL_PORT" \
    -u "$MYSQL_USER" \
    -D "$MYSQL_DB" \
    --init-command="SET @fixture_voucher_id=${VOUCHER_ID}; SET @fixture_stock=${K6_STOCK};" \
    < "$REPO_ROOT/loadtest/k6/reset-seckill-baseline.sql"

  printf 'syncing redis stock...\n'
  redis_exec SET "seckill:stock:${VOUCHER_ID}" "$K6_STOCK"
  redis_exec DEL "seckill:order:${VOUCHER_ID}"
else
  printf 'skipping token generation and baseline reset...\n'
fi

if [[ "$PREPARE_ONLY" -ne 0 ]]; then
  exit 0
fi

printf 'running k6 benchmark...\n'
K6_OUTPUT_FILE="$(mktemp)"

set +e
(
  cd "$REPO_ROOT"
  env -u K6_VUS -u K6_ITERATIONS -u K6_STAGES \
    BENCHMARK_QPS="$K6_QPS" BENCHMARK_DURATION="$K6_DURATION" BENCHMARK_TOKEN_COUNT="$K6_TOKEN_COUNT" BASE_URL="$BASE_URL" \
    k6 run loadtest/k6/seckill-benchmark.js
) 2>&1 | tee "$K6_OUTPUT_FILE"
k6_exit_code=${PIPESTATUS[0]}
set -e

if [[ "$k6_exit_code" -ne 0 ]]; then
  rm -f "$K6_OUTPUT_FILE"
  exit "$k6_exit_code"
fi

successful_orders="$(awk -F': ' '/successful_orders/{print $2; exit}' "$K6_OUTPUT_FILE" | awk '{print $1}')"

if [[ "$SKIP_VERIFY" -ne 0 ]]; then
  rm -f "$K6_OUTPUT_FILE"
  exit 0
fi

printf 'verifying benchmark results...\n'

redis_stock="$(redis_exec GET "seckill:stock:${VOUCHER_ID}" | tr -d '\r')"
order_count="$(MYSQL_PWD="$MYSQL_PASSWORD" mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" -D "$MYSQL_DB" -N -s -e "SELECT COUNT(*) FROM tb_voucher_order WHERE voucher_id = ${VOUCHER_ID};" | tr -d '\r')"
distinct_user_count="$(MYSQL_PWD="$MYSQL_PASSWORD" mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" -D "$MYSQL_DB" -N -s -e "SELECT COUNT(DISTINCT user_id) FROM tb_voucher_order WHERE voucher_id = ${VOUCHER_ID};" | tr -d '\r')"

if [[ -z "$redis_stock" ]]; then
  printf 'verification failed: redis key seckill:stock:%s is missing\n' "$VOUCHER_ID" >&2
  rm -f "$K6_OUTPUT_FILE"
  exit 1
fi

for value_name in redis_stock order_count distinct_user_count; do
  if [[ ! ${!value_name} =~ ^[0-9]+$ ]]; then
    printf 'verification failed: %s is not numeric: %s\n' "$value_name" "${!value_name}" >&2
    rm -f "$K6_OUTPUT_FILE"
    exit 1
  fi
done

if [[ ! "$successful_orders" =~ ^[0-9]+$ ]]; then
  printf 'verification failed: successful_orders is not numeric: %s\n' "$successful_orders" >&2
  rm -f "$K6_OUTPUT_FILE"
  exit 1
fi

duplicate_count=$((order_count - distinct_user_count))
expected_remaining_stock=$((K6_STOCK - order_count))
verification_failed=0

printf 'redis remaining stock: %s\n' "$redis_stock"
printf 'mysql order count: %s\n' "$order_count"
printf 'mysql distinct user count: %s\n' "$distinct_user_count"
printf 'duplicate order count: %s\n' "$duplicate_count"
printf 'expected remaining stock: %s\n' "$expected_remaining_stock"
printf 'successful orders: %s\n' "$successful_orders"

if [[ "$redis_stock" -ne "$expected_remaining_stock" ]]; then
  printf 'stock consistency: FAIL\n' >&2
  verification_failed=1
else
  printf 'stock consistency: PASS\n'
fi

if [[ "$successful_orders" -le 0 ]]; then
  printf 'successful orders: FAIL\n' >&2
  verification_failed=1
else
  printf 'successful orders: PASS\n'
fi

if [[ "$duplicate_count" -eq 0 ]]; then
  printf 'one person one order: PASS\n'
else
  printf 'one person one order: FAIL\n' >&2
  verification_failed=1
fi

if [[ "${verification_failed:-0}" -ne 0 ]]; then
  rm -f "$K6_OUTPUT_FILE"
  exit 1
fi

rm -f "$K6_OUTPUT_FILE"
