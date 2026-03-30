# k6 Load Test Scaffold

This directory holds the input data and baseline-reset template for the k6 benchmark plan.

## Benchmark entrypoints

- `read-benchmark.js` will be the read-path benchmark for `GET /shop/:id`.
- `seckill-benchmark.js` will be the seckill benchmark for `POST /voucher-order/seckill/:id`.
- `run-seckill-benchmark.sh` runs the `1000 qps / 200 stock` seckill flow.

The seckill benchmark uses `constant-arrival-rate` so requests arrive at a fixed QPS.

## Data files

- `data/shop-ids.csv` provides shop IDs for the read benchmark.
- `data/token-users.csv` provides user IDs and tokens for the seckill benchmark.
- `data/fixture-voucher.json` defines the fixture voucher used by seckill runs.

## Baseline reset flow

Before each seckill run, apply `reset-seckill-baseline.sql` against the local database.
Set `@fixture_stock` through `mysql --init-command` to match the target run size, then restore the fixture voucher stock and remove historical orders for that voucher so each run starts from the same baseline.

The one-command flow also syncs Redis with `seckill:stock:<voucherId>` so the Lua precheck uses the same stock value as MySQL.

Replace the placeholder voucher ID and stock values in the fixture files before using them in a real benchmark.

## Acceptance checks

- Read benchmark: `http_req_failed < 1%`, `p95 < 200ms`.
- Seckill benchmark: system errors `<= 1%`, and post-run SQL must confirm no oversell and one order per user.

## Token generation

Generate fresh tokens with `K6_TOKEN_COUNT=1000 go test -tags k6data ./internal/test -run TestGenerate1000Tokens -v` before a seckill run.

Use `K6_QPS`, `K6_STOCK`, `K6_DURATION`, and `K6_TOKEN_COUNT` to tune the benchmark. The default run is `1000 qps`, `200 stock`, `1m` duration, and `1000` tokens.

## One-command flow

Run the full benchmark sequence with:

```bash
bash loadtest/k6/run-seckill-benchmark.sh
```

Override `MYSQL_CONTAINER`, `REDIS_CONTAINER`, `MYSQL_USER`, `MYSQL_PASSWORD`, `MYSQL_DB`, `K6_VOUCHER_ID`, `K6_QPS`, `K6_STOCK`, `K6_DURATION`, `K6_TOKEN_COUNT`, or `BASE_URL` if needed.
