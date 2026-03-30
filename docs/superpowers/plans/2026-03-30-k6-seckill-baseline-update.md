# k6 秒杀基线更新 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将秒杀压测固定为 `1000 qps / 200 stock`，并在压测前自动加载测试 SQL 和 Redis 库存基线。

**Architecture:** 继续沿用 `loadtest/k6/run-seckill-benchmark.sh` 作为唯一入口，在进入 k6 之前完成 MySQL 基线重置和 Redis 库存写入。同步把默认基线数据和文档说明更新到同一套 200 库存配置，避免脚本、说明和数据文件出现不一致。

**Tech Stack:** Bash, MySQL, Redis, k6, Go test, Markdown

---

### Task 1: Align the benchmark baseline

**Files:**
- Modify: `loadtest/k6/reset-seckill-baseline.sql`
- Modify: `loadtest/k6/data/fixture-voucher.json`

- [ ] **Step 1: Update the default fixture stock**

Set the SQL fallback stock and fixture metadata to `200` so the benchmark baseline matches the fixed seckill scenario.

- [ ] **Step 2: Verify the baseline values stay parameterized**

Run: `sed -n '1,80p' loadtest/k6/reset-seckill-baseline.sql`

Expected: The SQL still accepts `@fixture_voucher_id` and `@fixture_stock`, with `200` as the default fallback.

### Task 2: Document the one-command flow

**Files:**
- Modify: `README.md`
- Modify: `loadtest/k6/README.md`

- [ ] **Step 1: Describe the fixed seckill run**

Document that the default seckill benchmark is `1000 qps / 200 stock` and that the one-command script resets MySQL and Redis before running k6.

- [ ] **Step 2: Verify the documented command matches the script**

Run: `sed -n '117,140p' README.md`

Expected: The README command and parameter descriptions match the shell script defaults.

### Task 3: Keep the entrypoint explicit

**Files:**
- Modify: `loadtest/k6/run-seckill-benchmark.sh`

- [ ] **Step 1: Make the preload sequence explicit**

Keep the existing MySQL reset and Redis `SET` steps ahead of `k6 run`, and ensure the defaults remain `K6_QPS=1000` and `K6_STOCK=200`.

- [ ] **Step 2: Verify the flow end to end**

Run: `bash loadtest/k6/run-seckill-benchmark.sh`

Expected: The script regenerates tokens, loads the SQL baseline, writes Redis stock, and then starts the k6 seckill run.
