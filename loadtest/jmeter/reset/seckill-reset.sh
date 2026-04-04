#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

MYSQL_HOST="${HMDP_MYSQL_HOST:-127.0.0.1}"
MYSQL_PORT="${HMDP_MYSQL_PORT:-3306}"
MYSQL_USER="${HMDP_MYSQL_USERNAME:-root}"
MYSQL_PASSWORD="${HMDP_MYSQL_PASSWORD:-123456}"
MYSQL_DB="${HMDP_MYSQL_DBNAME:-hmdp}"
REDIS_HOST="${HMDP_REDIS_HOST:-127.0.0.1}"
REDIS_PORT="${HMDP_REDIS_PORT:-6379}"
REDIS_PASSWORD="${HMDP_REDIS_PASSWORD:-}"
REDIS_DB="${HMDP_REDIS_DB:-0}"
VOUCHER_ID="${VOUCHER_ID:-1}"
STOCK="${STOCK:-200}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --voucher-id)
      VOUCHER_ID="$2"
      shift 2
      ;;
    --stock)
      STOCK="$2"
      shift 2
      ;;
    *)
      printf 'unknown option: %s\n' "$1" >&2
      exit 1
      ;;
  esac
done

if [[ ! "$VOUCHER_ID" =~ ^[0-9]+$ ]]; then
  printf 'invalid voucher id: %s\n' "$VOUCHER_ID" >&2
  exit 1
fi
if [[ ! "$STOCK" =~ ^[0-9]+$ ]] || [[ "$STOCK" -eq 0 ]]; then
  printf 'invalid stock: %s\n' "$STOCK" >&2
  exit 1
fi

for cmd in mysql redis-cli; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    printf 'missing required command: %s\n' "$cmd" >&2
    exit 1
  fi
done

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

MYSQL_PWD="$MYSQL_PASSWORD" mysql \
  -h "$MYSQL_HOST" \
  -P "$MYSQL_PORT" \
  -u "$MYSQL_USER" \
  -D "$MYSQL_DB" \
  --init-command="SET @fixture_voucher_id=${VOUCHER_ID}; SET @fixture_stock=${STOCK};" \
  <"$REPO_ROOT/loadtest/k6/reset-seckill-baseline.sql"

redis_exec SET "seckill:stock:${VOUCHER_ID}" "$STOCK" >/dev/null
redis_exec DEL "seckill:order:${VOUCHER_ID}" >/dev/null

printf 'seckill reset complete: voucher=%s stock=%s\n' "$VOUCHER_ID" "$STOCK"
