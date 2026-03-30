# k6 高并发压测实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 落地两类 k6 主压测场景，分别验证纯读链路高并发能力与秒杀链路高并发下的性能、 不超卖和一人一单正确性。

**Architecture:** 用一个独立的 `loadtest/k6` 目录承载压测脚本、输入数据样例和运行说明。读链路与秒杀链路共享同一套配置入口，但各自拥有明确的请求模型、阈值和结果校验逻辑；秒杀场景在压测结束后增加数据库最终态核验，确保异步 MQ 消费完成后再判定正确性。

**Tech Stack:** k6, Go test, Redis, MySQL, RocketMQ, Gin

---

### Task 1: 约定压测目录和输入数据

**Files:**
- Create: `loadtest/k6/README.md`
- Create: `loadtest/k6/data/shop-ids.csv`
- Create: `loadtest/k6/data/token-users.csv`
- Create: `loadtest/k6/data/fixture-voucher.json`
- Create: `loadtest/k6/reset-seckill-baseline.sql`

- [ ] **Step 1: Write the failing test / placeholder**

先创建空的目录和样例数据文件，确保后续脚本有稳定的数据入口。`shop-ids.csv` 只放存在的商户 ID 样例，`token-users.csv` 只放压测账号 token 样例，`fixture-voucher.json` 记录秒杀券 ID、库存基线和清理说明。

- [ ] **Step 2: Run a quick existence check**

Run: `ls loadtest/k6 && ls loadtest/k6/data`
Expected: 能看到 `README.md` 和 3 个数据文件。

- [ ] **Step 3: Write minimal content**

在 `README.md` 里说明：脚本如何选择数据文件、如何重置秒杀券库存、如何执行两类场景。

- [ ] **Step 4: Write the reset SQL**

在 `reset-seckill-baseline.sql` 中写清楚：将指定秒杀券库存恢复为固定值，并删除该券的历史订单，确保每轮压测都有相同基线。

- [ ] **Step 5: Verify files are readable**

Run: `sed -n '1,120p' loadtest/k6/README.md`
Expected: 内容完整，无路径歧义。

### Task 2: 实现纯读链路 k6 场景

**Files:**
- Create: `loadtest/k6/read-benchmark.js`
- Modify: `loadtest/k6/README.md`

- [ ] **Step 1: Write the failing test / placeholder**

在脚本里定义 `GET /shop/:id` 场景，读取存在的商户 ID，按 `1 分钟预热 + 5 分钟稳态` 和 `50 -> 200 VUs` 的负载模型运行。

- [ ] **Step 2: Run the script with a dry configuration**

Run: `k6 run loadtest/k6/read-benchmark.js`
Expected: 如果环境变量未提供，脚本应明确报错并提示需要的参数；如果参数齐全，则能发起请求。

- [ ] **Step 3: Implement threshold checks**

把读链路的阈值写死为 `http_req_failed < 1%`、`p95 < 200ms`，并保留结果摘要输出。

- [ ] **Step 4: Verify output**

Run: `k6 run --summary-trend-stats='avg,min,med,max,p(90),p(95),p(99)' loadtest/k6/read-benchmark.js`
Expected: 输出包含请求量、失败率、p95/p99。

### Task 3: 实现秒杀链路 k6 场景

**Files:**
- Create: `loadtest/k6/seckill-benchmark.js`
- Create: `loadtest/k6/seckill-verify.sql`
- Modify: `loadtest/k6/README.md`

- [ ] **Step 1: Write the failing test / placeholder**

在脚本里定义 `POST /voucher-order/seckill/:id` 场景，使用随机账号池、固定秒杀券 ID、`30 秒预热 + 1 分钟冲顶 + 2 分钟回落` 的负载模型。

- [ ] **Step 2: Add correctness hooks**

脚本在结束后输出：发送成功数、业务拒绝数、系统错误率，并提示进入数据库核验阶段。

- [ ] **Step 3: Add k6 thresholds**

把秒杀链路阈值写成可执行约束：系统错误率 `<= 1%`，业务拒绝单独计数，压测结束后需要等待 MQ 积压清空。

- [ ] **Step 4: Add post-run verification SQL**

在 `seckill-verify.sql` 中写清楚核验项：同一用户的订单数、券对应总订单数、库存是否为负、是否存在重复 `user_id + voucher_id`。

- [ ] **Step 5: Reset the benchmark baseline**

Run: `mysql -uroot -p123456 hmdp < loadtest/k6/reset-seckill-baseline.sql`
Expected: 秒杀券库存和历史订单被重置到固定基线。

- [ ] **Step 6: Run the script**

Run: `k6 run loadtest/k6/seckill-benchmark.js`
Expected: 在库存基线正确且账号池有效时，脚本能完成压测并输出可核验结果。

- [ ] **Step 7: Wait for RocketMQ drain**

Run: 轮询 RocketMQ backlog 或 consumer lag，直到积压归零；若超过 `2 分钟` 仍未归零则判失败。
Expected: 压测结果进入稳定最终态后再进行数据库核验。

- [ ] **Step 8: Run post-run DB verification**

Run: `mysql -uroot -p123456 hmdp < loadtest/k6/seckill-verify.sql`
Expected: 核验结果能判断是否满足“不超卖”和“一人一单”。

### Task 4: 补齐数据准备与运行文档

**Files:**
- Modify: `internal/test/token_gen_test.go`
- Modify: `README.md`
- Modify: `loadtest/k6/README.md`

- [ ] **Step 1: Write the failing test / placeholder**

确认 token 生成测试能导出足够的压测账号，并且生成格式与 k6 一致。

- [ ] **Step 2: Update the export path**

把 `internal/test/token_gen_test.go` 的输出目标改为基于仓库根目录解析后的 `loadtest/k6/data/token-users.csv`，避免依赖 `go test` 的当前工作目录。实现时先解析仓库根目录，再拼接输出路径，确保从 package 目录运行也能写到正确位置。

- [ ] **Step 3: Document the setup flow**

在 README 中补充：如何准备商户 ID 样本、如何生成 token、如何重置秒杀券库存、如何区分读压测和秒杀压测结果。

- [ ] **Step 4: Verify end-to-end flow**

Run: `go test ./internal/test -run TestGenerate1000Tokens -v`
Run: `k6 run loadtest/k6/read-benchmark.js`
Run: `k6 run loadtest/k6/seckill-benchmark.js`
Expected: 三者能串起来完成一次完整压测演练。

- [ ] **Step 5: Final review**

确认 README、脚本和 SQL 文件里的路径、环境变量和阈值完全一致。
