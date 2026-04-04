# k6 Load Test Scaffold

This directory holds the input data and baseline-reset template for the k6 benchmark plan.

## Benchmark entrypoints

- `read-benchmark.js` will be the read-path benchmark for `GET /shop/:id`.
- `seckill-benchmark.js` will be the seckill benchmark for `POST /voucher-order/seckill/:id`.
- `run-seckill-benchmark.sh` runs the seckill flow and accepts CLI overrides for QPS and stock.

The seckill benchmark uses `constant-arrival-rate` so requests arrive at a fixed QPS.

## Data files

- `data/shop-ids.csv` provides shop IDs for the read benchmark.
- `data/token-users.csv` provides user IDs and tokens for the seckill benchmark.
- `data/fixture-voucher.json` defines the fixture voucher used by seckill runs.

## Baseline reset flow

Before each seckill run, apply `reset-seckill-baseline.sql` against the target MySQL instance.
The default flow connects to MySQL and Redis over TCP, resets the baseline, then writes `seckill:stock:<voucherId>` into Redis and clears `seckill:order:<voucherId>` so the benchmark starts from a clean state.
After k6 finishes, the same script checks Redis remaining stock, MySQL order count, k6 successful orders, and whether any user placed more than one order for the same voucher.

Replace the placeholder voucher ID and stock values in the fixture files before using them in a real benchmark.

## Acceptance checks

- Read benchmark: `http_req_failed < 1%`, `p95 < 200ms`.
- Seckill benchmark: system errors `<= 1%`, and post-run SQL must confirm no oversell and one order per user.

## Token generation

Generate fresh tokens with `K6_TOKEN_COUNT=1000 go test -tags k6data ./internal/test -run TestGenerate1000Tokens -v` before a seckill run.

Use `bash loadtest/k6/run-seckill-benchmark.sh --qps 1000 --stock 1000` to override the main benchmark values. The shell wrapper still accepts `K6_QPS`, `K6_STOCK`, `K6_DURATION`, and `K6_TOKEN_COUNT` as defaults, and the k6 script reads `BENCHMARK_QPS`, `BENCHMARK_DURATION`, and `BENCHMARK_TOKEN_COUNT` internally.

To target remote MySQL/Redis from a local laptop, set `HMDP_MYSQL_HOST`, `HMDP_MYSQL_PORT`, `HMDP_MYSQL_USERNAME`, `HMDP_MYSQL_PASSWORD`, `HMDP_MYSQL_DBNAME`, `HMDP_REDIS_HOST`, `HMDP_REDIS_PORT`, `HMDP_REDIS_PASSWORD`, and `HMDP_REDIS_DB` before running the benchmark script. Use `PREPARE_ONLY=1` on the remote machine to seed tokens and reset the baseline, then run the local benchmark with `SKIP_PREPARE=1` and `SKIP_VERIFY=1`.

## One-command flow

Run the full benchmark sequence with:

```bash
bash loadtest/k6/run-seckill-benchmark.sh
```

Override `BASE_URL` if needed. For benchmark parameters, prefer the CLI flags on `run-seckill-benchmark.sh`.
