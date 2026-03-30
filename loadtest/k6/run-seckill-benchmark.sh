#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

MYSQL_BIN="${MYSQL_BIN:-mysql}"
MYSQL_CONTAINER="${MYSQL_CONTAINER:-hmdp-mysql}"
REDIS_CONTAINER="${REDIS_CONTAINER:-hmdp-redis}"
MYSQL_USER="${MYSQL_USER:-root}"
MYSQL_PASSWORD="${MYSQL_PASSWORD:-123456}"
MYSQL_DB="${MYSQL_DB:-hmdp}"
BASE_URL="${BASE_URL:-http://127.0.0.1:8081}"
VOUCHER_ID="${K6_VOUCHER_ID:-1}"
K6_QPS="${K6_QPS:-1000}"
K6_STOCK="${K6_STOCK:-200}"
K6_DURATION="${K6_DURATION:-1m}"
K6_TOKEN_COUNT="${K6_TOKEN_COUNT:-1000}"

for tool in go k6 docker; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    printf 'missing required command: %s\n' "$tool" >&2
    exit 1
  fi
done

printf '\n=== seckill benchmark: %s qps / %s stock ===\n' "$K6_QPS" "$K6_STOCK"

printf 'preparing token data...\n'

(
  cd "$REPO_ROOT"
  K6_TOKEN_COUNT="$K6_TOKEN_COUNT" go test -tags k6data ./internal/test -run TestGenerate1000Tokens -v
)

printf 'resetting mysql baseline...\n'
docker exec -e MYSQL_PWD="$MYSQL_PASSWORD" -i "$MYSQL_CONTAINER" "$MYSQL_BIN" \
  -u "$MYSQL_USER" \
  -D "$MYSQL_DB" \
  --init-command="SET @fixture_voucher_id=${VOUCHER_ID}; SET @fixture_stock=${K6_STOCK};" \
  < "$REPO_ROOT/loadtest/k6/reset-seckill-baseline.sql"

printf 'syncing redis stock...\n'
docker exec -i "$REDIS_CONTAINER" redis-cli SET "seckill:stock:${VOUCHER_ID}" "$K6_STOCK"

printf 'running k6 benchmark...\n'
(
  cd "$REPO_ROOT"
env -u K6_VUS -u K6_ITERATIONS -u K6_STAGES \
    BENCHMARK_QPS="$K6_QPS" BENCHMARK_DURATION="$K6_DURATION" BENCHMARK_TOKEN_COUNT="$K6_TOKEN_COUNT" BASE_URL="$BASE_URL" \
    k6 run loadtest/k6/seckill-benchmark.js
)
