# Kafka 替换为 RocketMQ 设计说明

## 背景

当前项目仅在秒杀券异步下单链路中使用 Kafka。消息在 Lua 预扣库存成功后发送，消费者异步落库，应用退出时关闭生产者并停止消费者。

本次需求是在不改变现有业务语义的前提下，将 Kafka 替换为标准方案的 RocketMQ。

## 目标

- 将秒杀下单链路中的 Kafka 替换为 Apache RocketMQ Go SDK。
- 保持“抢单成功后立即返回订单号”的现有接口行为不变。
- 保持“消费成功才确认，消费失败可重试”的现有处理语义不变。
- 保持现有消息体格式 `VoucherOrder JSON` 不变。
- 保持业务正确性仍然由 Redis 预扣、一人一单校验、分布式锁和数据库事务共同保障。
- 完成全量文档迁移：将 `README.md` 中所有面向当前实现的 Kafka 描述替换为 RocketMQ 语义说明，避免“代码已迁移、文档仍旧 Kafka”的不一致状态。
- 明确消费异常边界：业务失败返回重试；结构性坏消息（反序列化失败）记录后跳过，避免毒消息无限重试。

## 非目标

- 不引入 Kafka 和 RocketMQ 的双写、双读灰度逻辑。
- 不对秒杀业务流程做额外重构。
- 不修改订单消息的数据结构和业务字段。
- 不围绕 MQ 抽象出通用消息总线层。
- 不保留“当前实现仍为 Kafka”的运行文档描述；本次运行文档范围限定为 `README.md` 与 `AGENTS.md`，仅允许在迁移设计类文档中保留 Kafka 对比背景。

## 当前现状

当前 Kafka 相关实现集中在以下位置：

- `internal/global/kafka.go`：初始化全局 `KafkaWriter` 并提供关闭方法。
- `internal/service/voucher_order.go`：生产秒杀订单消息、启动 Kafka 消费者、消费后执行业务落库。
- `config/config.go` / `config/config.yaml`：维护 Kafka 配置。
- `cmd/api/main.go`：优雅关闭时停止消费者并关闭生产者。

当前业务关键语义如下：

1. 接口层执行 Lua 脚本完成库存预扣和一人一单校验。
2. 生成订单 ID 和订单消息。
3. 发送 Kafka 消息。
4. 发送成功后立即返回订单号。
5. 消费者读取消息后调用 `handleVoucherOrder` 执行加锁、查重、扣库存、写订单。
6. 处理成功后确认消费；失败则等待后续重投。

## 方案概述

采用“最小侵入、语义等价替换”的方案，直接将 Kafka 接入替换为 RocketMQ，不对业务流程和消息格式做额外变更。

实现上分为四部分：

1. 用 RocketMQ Producer 替换 Kafka Writer。
2. 用 RocketMQ PushConsumer 替换 Kafka Reader。
3. 用 RocketMQ 配置替换现有 Kafka 配置。
4. 调整应用启动和关闭逻辑，完成 RocketMQ 客户端生命周期管理。

## 架构设计

### 1. 全局 MQ 客户端管理

新增 `internal/global/rocketmq.go` 管理 RocketMQ 生产者与消费者的全局实例及关闭逻辑。

职责：

- 初始化标准 RocketMQ Producer。
- 暴露发送消息需要的全局 producer。
- 提供关闭 producer、shutdown consumer 的统一方法。
- 避免在业务层直接拼装底层客户端初始化参数。

说明：

- 现有 `internal/global/kafka.go` 将被删除或由新文件替代，避免命名与实现不一致。
- 生命周期管理统一放在 `internal/global`，业务层仅关心“发送订单消息”和“启动订单消费者”。
- 启停唯一归口：`cmd/api/main.go` 负责初始化 producer/consumer、触发 `StartVoucherOrderConsumer`，并在退出时执行“停止订阅 -> 关闭 consumer -> 关闭 producer”。
- 启动失败策略：producer 或 consumer 初始化失败时直接终止进程启动，避免服务在消息链路不可用时继续对外提供秒杀能力。

### 2. 订单消息生产

在 `internal/service/voucher_order.go` 中，将当前 `SeckillVoucherByRedisAndKafka` 替换为基于 RocketMQ 的实现。

保留现有业务顺序：

1. 校验登录态。
2. 生成订单 ID。
3. 执行 Lua 脚本完成库存预扣和重复下单校验。
4. 构造 `VoucherOrder`。
5. JSON 序列化消息体。
6. 发送 RocketMQ 消息。
7. 发送成功后返回订单号；发送失败则回滚 Redis 预扣。

发送策略：

- 使用同步发送，确保只有消息真正发送成功才向前端返回成功。
- `Keys` 固定为两个值：`userId` 与 `orderId`（字符串化），便于日志检索和消息追踪。
- Topic 沿用单一订单主题，仅承载 `voucher-order` 类型消息。

### 3. 订单消息消费

在 `internal/service/voucher_order.go` 中，将 `StartVoucherOrderConsumer` 改为 RocketMQ `PushConsumer` 模式。

消费逻辑保持不变：

- 收到消息后反序列化 `VoucherOrder`。
- 调用 `handleVoucherOrder` 完成加锁、查重、扣减库存和创建订单。
- 业务处理成功时返回 `ConsumeSuccess`。
- 业务处理失败时返回 `ConsumeRetryLater`，交由 RocketMQ 重试。
- 反序列化失败视为坏消息，记录完整上下文后返回 `ConsumeSuccess` 跳过，避免无限重试阻塞队列。

语义映射如下：

- Kafka “处理成功后提交 offset” 对应 RocketMQ “返回 `ConsumeSuccess`”。
- Kafka “处理失败不提交，等待重投” 对应 RocketMQ “返回 `ConsumeRetryLater`”。

结论：

虽然两者底层机制不同，但对当前业务来说，消费确认语义是等价的。

### 4. 应用关闭

在 `cmd/api/main.go` 中调整优雅关闭逻辑：

- 保留现有 HTTP 服务优雅关闭。
- 保留停止订单消费者的流程。
- 将 `CloseKafkaWriter` 替换为 RocketMQ producer 和 consumer 的关闭方法。

要求：

- 重复关闭必须安全。
- 停止过程中不得因空指针或重复调用导致 panic。

## 配置设计

### 新配置结构

将现有：

```yaml
kafka:
  brokers:
    - "127.0.0.1:9092"
  topic: "voucher-order-topic"
  group_id: "voucher-order-group"
```

替换为类似：

```yaml
rocketmq:
  name_servers:
    - "127.0.0.1:9876"
  topic: "voucher-order-topic"
  producer_group: "voucher-order-producer"
  consumer_group: "voucher-order-consumer"
```

对应 `config/config.go` 中的 `KafkaConfig` 调整为 `RocketMQConfig`。

### 字段映射

- `brokers` -> `name_servers`
- `topic` -> `topic`
- `group_id` -> `consumer_group`

新增：

- `producer_group`

原因：

- RocketMQ 中 producer 和 consumer 的 group 含义不同。
- 为避免未来扩展受限，生产组和消费组应显式分离。

## 消息模型与顺序性判断

当前 Kafka 实现使用 `userId` 作为消息 key，目的是让同一用户消息尽量落到同一 partition。

替换为 RocketMQ 后：

- 会继续把 `userId` 放入消息 `Keys` 用于追踪。
- 本次不引入顺序消息或自定义队列选择器。

判断依据：

- 当前业务正确性并不依赖 MQ 的严格分区顺序。
- 一人一单和并发安全依赖的是 Lua 预扣、Redis 锁、查重逻辑和数据库事务。
- 因此不需要为了“等价替换”额外引入顺序消息复杂度。

如果未来明确需要用户级严格有序消费，再单独评估顺序消息方案。

## 错误处理设计

### 生产端

- JSON 序列化失败：直接回滚 Redis 预扣并返回失败。
- RocketMQ 发送失败：记录错误日志，回滚 Redis 预扣，返回“系统繁忙，请稍后再试”。

Redis 预扣回滚定义（由 `rollback.lua` 承担）：

- 回补库存计数。
- 回滚用户下单占位标记。
- 保证“发送失败后用户可再次发起下单”的可恢复语义。

### 消费端

- 消息反序列化失败：记录错误日志，返回成功以跳过坏消息，避免无限重试。
- 业务处理失败：记录错误日志并返回重试状态，由 RocketMQ 进行后续重投。
- 重复下单：保持现有幂等语义，视为业务已处理完成，不作为失败重试。
- 订阅策略：使用 `Tag=*` 覆盖当前主题下订单消息；本次不引入多 tag 路由。

## 测试设计

### 单元/行为测试

优先补充与消息发送失败回滚相关的测试，覆盖以下行为：

- 消息发送失败时触发 Redis 预扣回滚。
- 消费成功路径返回 `ConsumeSuccess`，且不会触发 RocketMQ 重试。
- 消息体序列化与反序列化兼容当前 `VoucherOrder` 结构。

### 集成验证

在本地 RocketMQ 服务可用时验证：

1. 秒杀接口成功后立即返回订单号。
2. RocketMQ 中可看到订单消息被发送。
3. 消费成功后数据库中生成订单记录。
4. 人为制造消费失败时消息能够重试。
5. 重复下单时仍然被拦截。

### 基础回归

- `go test ./...`
- 至少保证项目编译通过，已有测试不因 MQ 替换失效。

### 文档一致性验证

- 在仓库范围执行关键字扫描，确保运行文档中不再出现 Kafka 作为“当前实现”的表述。
- 对 README 采用“语义重写”而非机械替换，至少覆盖以下章节：技术栈、环境依赖、配置键、故障排查、秒杀链路说明、选型说明、代码示例、面试表述。
- 允许 `docs/superpowers/specs` 与 `docs/superpowers/plans` 保留 Kafka 迁移背景描述；其余运行文档需以 RocketMQ 为当前实现。

## 风险与缓解

### 风险 1：消费者生命周期管理不稳定

消费者生命周期必须由 `cmd/api/main.go` 统一编排；若存在历史 `service.init()` 启动路径，需要在本次迁移中移除，避免双启动或初始化竞态。

缓解：

- 显式保持单入口：`InitRocketMQProducer` -> `InitRocketMQConsumer` -> `StartVoucherOrderConsumer`。
- 显式保持单出口：`StopVoucherOrderConsumer` -> `CloseRocketMQConsumer` -> `CloseRocketMQProducer`。
- 任一步骤失败立即中止启动并输出结构化错误日志。

### 风险 2：RocketMQ 重试语义与 Kafka offset 模型不同

两者实现机制不同，若处理不当，可能出现错误消息无限重试或不必要丢弃。

缓解：

- 明确区分“坏消息”与“业务失败”。
- 仅对可重试的业务失败返回 `ConsumeRetryLater`。

### 风险 3：日志排障能力下降

替换 MQ 后，若日志字段不足，排查积压、重复消费和发送失败会变难。

缓解：

- 在发送和消费日志中补充 `topic`、`orderId`、`userId`、消息 key 等关键信息。

### 风险 4：切换窗口旧消息积压导致语义争议

若 Kafka 侧仍存在未消费消息，直接切换 RocketMQ 可能造成“旧链路订单未落库”或“双链路重复消费”的争议。

缓解：

- 切换前冻结 Kafka 新写入入口，仅保留消费清尾。
- 对 Kafka backlog 做一次可观测清尾（或导出对账）后再停 Kafka 消费者。
- 切换后以 RocketMQ 作为唯一写入与消费链路。
- 若需回滚，只回滚到“单链路 Kafka”或“单链路 RocketMQ”，避免双链路并跑。

## 验收标准

以下条件全部满足即视为本次迁移完成：

1. 代码层：运行路径（`cmd/`、`internal/`、`config/`、`go.mod/go.sum`）不再依赖 Kafka 客户端与 Kafka 配置键。
   - 允许 `docs/superpowers/specs`、`docs/superpowers/plans` 中保留迁移背景描述。
   - 不要求清除所有历史字符串或注释中的 Kafka 字样，但运行时代码路径不得引用 Kafka SDK、Kafka 配置结构或 Kafka 启停逻辑。
2. 行为层：秒杀接口仍满足“预扣成功后快速返回订单号”；发送失败触发 Redis 预扣回滚；消费业务失败可重试。
3. 异常边界：坏消息（反序列化失败）被记录并跳过，且不会触发无限重试。
4. 文档层：`README.md` 全量以 RocketMQ 作为当前实现，不保留“当前使用 Kafka”的描述。
5. 验证层：
   - 通过 `go test ./...`。
   - 启动验证 `go run ./cmd/api/main.go`，确认 RocketMQ 初始化与关闭流程无 panic。
   - 文档扫描范围固定为 `README.md` 与 `AGENTS.md`；关键字扫描验证这两个运行文档不再声明 Kafka 为当前实现。

## 文件变更范围

预计涉及以下文件：

- 修改：`config/config.go`
- 修改：`config/config.yaml`
- 删除或替换：`internal/global/kafka.go`
- 新增：`internal/global/rocketmq.go`
- 修改：`internal/service/voucher_order.go`
- 修改：`cmd/api/main.go`
- 修改：`README.md`
- 修改：`go.mod`
- 修改：`go.sum`
- 允许补充修改：`AGENTS.md`（若涉及运行指引中的 MQ 描述一致性修订）

## 设计结论

本次采用“最小侵入的 RocketMQ 替换”方案，以标准 Apache RocketMQ Go SDK 替换 Kafka 的生产和消费能力，保持秒杀下单链路的接口行为、消息体格式和成功/失败语义基本不变。

该方案改动集中、风险可控，适合当前仓库只有单一订单消息链路的现状。后续如项目出现更多消息主题和消费场景，再评估是否引入统一 MQ 抽象层。
