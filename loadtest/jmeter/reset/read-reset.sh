#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

REDIS_HOST="${HMDP_REDIS_HOST:-127.0.0.1}"
REDIS_PORT="${HMDP_REDIS_PORT:-6379}"
REDIS_PASSWORD="${HMDP_REDIS_PASSWORD:-}"
REDIS_DB="${HMDP_REDIS_DB:-0}"
SHOP_IDS_CSV="${SHOP_IDS_CSV:-${REPO_ROOT}/loadtest/k6/data/shop-ids.csv}"

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

if ! command -v redis-cli >/dev/null 2>&1; then
  printf 'missing required command: redis-cli\n' >&2
  exit 1
fi

if [[ ! -f "$SHOP_IDS_CSV" ]]; then
  printf 'shop ids csv not found: %s\n' "$SHOP_IDS_CSV" >&2
  exit 1
fi

while IFS=, read -r shop_id _; do
  shop_id="${shop_id//[[:space:]]/}"
  if [[ "$shop_id" =~ ^[0-9]+$ ]]; then
    redis_exec DEL "cache:shop:${shop_id}" >/dev/null
  fi
done <"$SHOP_IDS_CSV"

printf 'read reset complete: cache:shop:* keys from %s cleared\n' "$SHOP_IDS_CSV"
