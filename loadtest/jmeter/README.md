# JMeter A/B 压测说明

本目录用于执行 **顺序 A/B 压测**（先 A，重置后再 B），覆盖两类高并发场景：

- 高并发读场景
- 高并发写/秒杀场景

## 1. 场景与基线定义

### 读场景

- A 基线（直连 MySQL）：`GET /shop-abtest/direct-db/:id`
- B 方案（缓存链路）：`GET /shop/:id`

### 写/秒杀场景

- A 基线（单事务）：`POST /voucher-order-abtest/tx/:id`
  - 在一个数据库事务中完成：校验库存、扣减库存、创建订单
- B 方案（优化链路）：`POST /voucher-order/seckill/:id`
  - Redis + Lua + RocketMQ

## 2. 压测策略（固定口径）

- A/B 不并发执行，必须严格 `A -> reset -> B`
- 秒杀场景为保证横向可比性：每个 stage 开始前都会 reset，使 `stage1/stage2/stage3` 都从相同初始库存起跑
- 每阶段节奏（默认）：`Ramp-up 20s + Hold 60s + Cooldown 10s`
- 并发阶梯：
  - 读：`100 -> 300 -> 600 users`
  - 写：`500 -> 1000 -> 2000 users`
- 指标口径：重点关注 `QPS`、`Avg RT`、`P95`、`P99`、`Error Rate`

## 3. 目录结构

- `read-ab.jmx`：读场景 JMeter 测试计划
- `seckill-ab.jmx`：秒杀场景 JMeter 测试计划
- `run-read-ab.sh`：读场景一键执行（内含 A/B 顺序）
- `run-seckill-ab.sh`：秒杀场景一键执行（内含 A/B 顺序）
- `reset/read-reset.sh`：读场景 reset（清理 shop 缓存）
- `reset/seckill-reset.sh`：秒杀场景 reset（重置 MySQL 与 Redis 秒杀基线）
- `scripts/summarize-jtl.sh`：从 `results.jtl` 提取核心指标
- `report-template.md`：压测结果汇总模板

## 4. 前置条件

本机需安装：

- `jmeter`
- `mysql` 客户端（用于 reset 和一致性检查）
- `redis-cli`（用于 reset）
- `python3`（用于解析 JTL）

并确保网络可从本机访问目标服务与中间件。

## 5. 远程服务压测（推荐用法）

当服务部署在远程机器（例如 `work-ubuntu`）且你在本机压测时，必须显式指定目标地址。

### 读场景

```bash
BASE_HOST=work-ubuntu BASE_PORT=8081 \
bash loadtest/jmeter/run-read-ab.sh
```

### 写/秒杀场景

```bash
BASE_HOST=work-ubuntu BASE_PORT=8081 \
HMDP_MYSQL_HOST=work-ubuntu HMDP_REDIS_HOST=work-ubuntu \
bash loadtest/jmeter/run-seckill-ab.sh
```

仅测 B 组（跳过 A）：

```bash
AB_MODE=B \
BASE_HOST=work-ubuntu BASE_PORT=8081 \
HMDP_MYSQL_HOST=work-ubuntu HMDP_REDIS_HOST=work-ubuntu \
bash loadtest/jmeter/run-seckill-ab.sh
```

说明：

- `BASE_HOST/BASE_PORT`：JMeter HTTP 请求目标（你的 API 服务）
- `HMDP_MYSQL_HOST/HMDP_REDIS_HOST`：reset 与一致性检查的连接目标

如果远端不是默认账号/端口，继续补充：

- MySQL：`HMDP_MYSQL_PORT` `HMDP_MYSQL_USERNAME` `HMDP_MYSQL_PASSWORD` `HMDP_MYSQL_DBNAME`
- Redis：`HMDP_REDIS_PORT` `HMDP_REDIS_PASSWORD` `HMDP_REDIS_DB`

### 远程服务 + 本地压测时如何准备 token（关键）

当服务部署在远程、压测在本地执行时，`TOKEN_CSV` 必须来自同一套远程环境（远程 Redis）。推荐流程：

1) 在远程生成 token（写入远程 Redis）

```bash
ssh work-ubuntu
cd /path/to/hmdp-go
K6_TOKEN_COUNT=2000 go test ./internal/test -tags k6data -run TestGenerate1000Tokens -v
```

2) 拉取 token 文件到本地

```bash
scp work-ubuntu:/path/to/hmdp-go/loadtest/k6/data/token-users.csv \
  /Users/optizephyr/Codes/hmdp-go/loadtest/k6/data/token-users.csv
```

3) 本地先抽样验证 token 是否有效

```bash
curl -i -H "authorization: <token>" http://work-ubuntu:8081/user/me
```

4) 本地执行秒杀压测（请求打远程）

```bash
BASE_HOST=work-ubuntu BASE_PORT=8081 \
HMDP_MYSQL_HOST=work-ubuntu HMDP_REDIS_HOST=work-ubuntu \
TOKEN_CSV=loadtest/k6/data/token-users.csv \
bash loadtest/jmeter/run-seckill-ab.sh
```

注意：

- `BASE_*` 决定 API 请求目标。
- `HMDP_*` 用于 reset 和一致性检查。
- 三者必须一致：服务实例、Redis 实例、token 来源；否则容易全量 401。

## 6. 常用参数

- 通用：
  - `BASE_PROTOCOL`（默认 `http`）
  - `BASE_HOST`（默认 `127.0.0.1`）
  - `BASE_PORT`（默认 `8081`）
  - `RAMP_SECONDS`（默认 `20`）
  - `HOLD_SECONDS`（默认 `60`）
  - `COOLDOWN_SECONDS`（默认 `10`）
  - `READ_RESET_STRICT`（默认 `1`，设为 `0` 可在无 `redis-cli` 或 Redis 不可达时跳过读场景 reset）
  - `CONNECT_TIMEOUT_MS`（默认 `2000`，秒杀请求连接超时）
  - `RESPONSE_TIMEOUT_MS`（默认 `5000`，秒杀请求响应超时，避免线程长期挂起）
- 读场景：
  - `SHOP_IDS_CSV`（默认 `loadtest/k6/data/shop-ids.csv`）
- 秒杀场景：
  - `TOKEN_CSV`（默认 `loadtest/k6/data/token-users.csv`）
  - `VOUCHER_ID`（默认 `1`）
  - `STOCK`（默认 `200`）
  - `AUTH_CHECK_ENABLED`（默认 `1`，秒杀压测前先抽样校验 token 是否对目标环境有效）
  - `AUTH_CHECK_PATH`（默认 `/user/me`）
  - `AUTH_CHECK_SAMPLES`（默认 `3`）
  - `AUTH_CHECK_TIMEOUT_SECONDS`（默认 `5`）
  - `SERVICE_CHECK_ENABLED`（默认 `1`，秒杀压测前先做服务可用性探测）
  - `SERVICE_CHECK_PATH`（默认 `/shop/1`）
  - `SERVICE_CHECK_TIMEOUT_SECONDS`（默认 `3`）
  - `PROGRESS_INTERVAL_SECONDS`（默认 `10`，秒杀压测时每隔 N 秒打印一次 samples 进度）
  - `AB_MODE`（默认 `ALL`，可选 `ALL|A|B`，用于跑全量/A 组/B 组）

## 7. 输出结果

- 读场景输出：`loadtest/jmeter/out/read/`
- 秒杀场景输出：`loadtest/jmeter/out/seckill/`

每个 stage 目录包含：

- `results.jtl`：原始样本
- `dashboard/`：JMeter HTML 报告
- `summary.txt`：核心指标摘要

秒杀场景额外输出：

- 每个 stage 目录下均有 `consistency.txt`：MySQL 与 Redis 双侧一致性信息（订单数、去重用户数、重复下单数、预期库存、Redis 库存与下单集合对账差值）

## 8. 结果解读与报告

1. 先对比同一 stage 下 A/B 的 `QPS` 与 `P95/P99`
2. 再看错误率与尾延迟是否在高并发下恶化
3. 秒杀场景必须检查：
   - `duplicate_count == 0`（一人一单）
   - 无超卖（`actual_remaining_stock >= 0` 且与预期一致）

说明：秒杀脚本按 stage 级别 reset，因此请按 stage 分别解读对应目录下的 `consistency.txt`。

建议每个子场景执行多轮，使用中位数汇总到 `report-template.md`。

## 9. 故障排查

- `connection refused`：确认 `BASE_HOST/PORT`、MySQL、Redis 对本机可达
- `missing required command: redis-cli`：安装 `redis-cli`，或临时使用 `READ_RESET_STRICT=0` 跳过读场景 reset
- 秒杀 `order_count=0` 且 `error_rate=1.0000`：优先检查 `results.jtl` 是否大量 `401`；脚本现在会在正式压测前执行 token 鉴权预检并在失败时中止
- 秒杀看起来 `QPS` 很高但订单为 0：`seckill-ab.jmx` 已增加 `"success":true` 断言，优先查看 `results.jtl` 的断言失败详情，再结合 `consistency.txt` 的 Redis 对账字段定位是业务失败还是异步落库链路问题
- 开始即报 `service preflight failed`：说明目标 API 当前不可用/不健康，或 `BASE_HOST/BASE_PORT` 指错环境
- `results.jtl` 长时间不增长且进程不退出：通常是请求无超时导致线程等待；可调小 `RESPONSE_TIMEOUT_MS`（例如 `3000`）并重试
- 远程压测全量 401：优先确认 token 是否在远程环境生成，而不是本地环境生成
- 全量 401：确认 `TOKEN_CSV` 是否有效、`authorization` 头是否正确
- 秒杀全失败：确认券时间窗口、`VOUCHER_ID` 与 `STOCK` 是否匹配基线
- A/B 数据污染：确认是否严格执行了 `reset`（脚本默认会执行）

## 10. 一次完整压测执行清单（Checklist）

按下面顺序执行，避免 A/B 数据污染和口径不一致。

### A. 压测前准备

- [ ] 本机已安装 `jmeter`、`mysql`、`redis-cli`、`python3`
- [ ] 本机可访问远程 `work-ubuntu` 的 API/MySQL/Redis 端口
- [ ] 目标服务已启动，且新接口可用：
  - [ ] `GET /shop-abtest/direct-db/:id`
  - [ ] `GET /shop/:id`
  - [ ] `POST /voucher-order-abtest/tx/:id`
  - [ ] `POST /voucher-order/seckill/:id`
- [ ] 秒杀券配置确认：`VOUCHER_ID`、`STOCK`、活动时间窗口正确
- [ ] token 数据可用：`loadtest/k6/data/token-users.csv`

### B. 执行读场景 A/B（先 A 后 B）

- [ ] 执行命令：

```bash
BASE_HOST=work-ubuntu BASE_PORT=8081 \
bash loadtest/jmeter/run-read-ab.sh
```

- [ ] 产物检查：`loadtest/jmeter/out/read/` 下存在
  - [ ] `a_direct_db/stage*/summary.txt`
  - [ ] `b_cache/stage*/summary.txt`

### C. 执行写/秒杀场景 A/B（先 A 后 B）

- [ ] 执行命令：

```bash
BASE_HOST=work-ubuntu BASE_PORT=8081 \
HMDP_MYSQL_HOST=work-ubuntu HMDP_REDIS_HOST=work-ubuntu \
bash loadtest/jmeter/run-seckill-ab.sh
```

- [ ] 产物检查：`loadtest/jmeter/out/seckill/` 下存在
  - [ ] `a_tx_baseline/stage*/summary.txt`
  - [ ] `b_redis_lua_mq/stage*/summary.txt`
  - [ ] `a_tx_baseline/stage*/consistency.txt`
  - [ ] `b_redis_lua_mq/stage*/consistency.txt`

### D. 一致性与正确性检查（秒杀必做）

- [ ] `duplicate_count == 0`（一人一单）
- [ ] 无超卖（剩余库存不为负，且与预期一致）
- [ ] 错误率在可接受范围内（关注高并发 stage3）

### E. 结果汇总与结论

- [ ] 按 stage 维度对比 A/B：`QPS`、`Avg`、`P95`、`P99`、`Error Rate`
- [ ] 将结果填入 `loadtest/jmeter/report-template.md`
- [ ] 每个子场景至少重复 3 轮，使用中位数作为最终结论
- [ ] 明确结论：在哪些并发档位 B 显著优于 A，是否出现长尾或错误率拐点
