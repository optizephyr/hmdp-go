# RocketMQ Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the project's Kafka-based voucher-order messaging path with standard Apache RocketMQ while preserving the current seckill order behavior and failure semantics.

**Architecture:** Keep the existing voucher-order business flow intact and swap only the MQ integration points. Centralize RocketMQ producer/consumer lifecycle in `internal/global`, then update `internal/service/voucher_order.go` to publish and consume the same `VoucherOrder` JSON payload with RocketMQ-specific success/retry handling.

**Boot Sequence:** `main -> InitRocketMQProducer -> InitRocketMQConsumer -> service.StartVoucherOrderConsumer -> HTTP serve`. Shutdown runs in reverse order: stop order-consumer loop/subscriptions first, then close RocketMQ consumer, then close RocketMQ producer.

**Tech Stack:** Go, Gin, GORM, Redis, Apache RocketMQ Go SDK, Go testing package

---

### Task 1: Replace Kafka Configuration And Global MQ Lifecycle

**Files:**
- Create: `internal/global/rocketmq.go`
- Modify: `config/config.go`
- Modify: `config/config.yaml`
- Modify: `cmd/api/main.go`
- Modify: `internal/service/voucher_order.go`
- Modify: `go.mod`
- Modify: `go.sum`
- Delete: `internal/global/kafka.go`
- Test: `go test ./config`

- [ ] **Step 1: Write the failing config/lifecycle test plan**

Document the expected compile-time shape before changing production code:

```go
type Config struct {
	Server   ServerConfig   `mapstructure:"server"`
	MySQL    MySQLConfig    `mapstructure:"mysql"`
	Redis    RedisConfig    `mapstructure:"redis"`
	RocketMQ RocketMQConfig `mapstructure:"rocketmq"`
}

type RocketMQConfig struct {
	NameServers   []string `mapstructure:"name_servers"`
	Topic         string   `mapstructure:"topic"`
	ProducerGroup string   `mapstructure:"producer_group"`
	ConsumerGroup string   `mapstructure:"consumer_group"`
}
```

And lifecycle surface:

```go
var RocketMQProducer rocketmq.Producer
var RocketMQConsumer rocketmq.PushConsumer

func CloseRocketMQProducer() error
func CloseRocketMQConsumer() error
func InitRocketMQProducer() error
func InitRocketMQConsumer() error
```

- [ ] **Step 2: Run package tests to confirm the old code does not satisfy the new surface**

Run: `go test ./config`
Expected: FAIL or compile errors because `RocketMQConfig` and `rocketmq` config loading do not exist yet.

- [ ] **Step 3: Add the RocketMQ dependency and replace config structures**

Update `go.mod`/`go.sum` to remove `github.com/segmentio/kafka-go` and add the standard RocketMQ SDK. Update `config/config.go` and `config/config.yaml` so the project reads:

```yaml
rocketmq:
  name_servers:
    - "127.0.0.1:9876"
  topic: "voucher-order-topic"
  producer_group: "voucher-order-producer"
  consumer_group: "voucher-order-consumer"
```

Production code in `internal/global/rocketmq.go` should:

```go
producer, err := rocketmq.NewProducer(
	producer.WithNameServer(config.GlobalConfig.RocketMQ.NameServers),
	producer.WithGroupName(config.GlobalConfig.RocketMQ.ProducerGroup),
)
if err != nil {
	panic(err)
}
if err := producer.Start(); err != nil {
	panic(err)
}
RocketMQProducer = producer
```

And define the consumer lifecycle surface in the same file, but do **not** auto-start real MQ clients inside package `init()` for testability. The implementation should prefer explicit startup from application boot code or a replaceable init hook. Target shape:

```go
consumer, err := rocketmq.NewPushConsumer(
	consumer.WithNameServer(config.GlobalConfig.RocketMQ.NameServers),
	consumer.WithGroupName(config.GlobalConfig.RocketMQ.ConsumerGroup),
)
if err != nil {
	return err
}
RocketMQConsumer = consumer
return nil
```

Also update `cmd/api/main.go` and the service startup path so runtime boot calls explicit init/start functions, while package tests can replace or skip them without requiring a real RocketMQ server.

Explicitly remove the current `internal/service/voucher_order.go` package `init()` startup path for the MQ consumer. After this task, consumer boot must happen only through the runtime boot sequence declared at the top of this plan.

- [ ] **Step 4: Run the targeted packages again**

Run: `go test ./config`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add config/config.go config/config.yaml cmd/api/main.go internal/service/voucher_order.go go.mod go.sum internal/global/rocketmq.go internal/global/kafka.go
git commit -m "refactor: replace kafka config with rocketmq"
```

### Task 2: Replace Voucher Order Message Publishing With RocketMQ

**Files:**
- Modify: `internal/service/voucher_order.go`
- Modify: `internal/handler/voucher_order.go`
- Create: `internal/service/voucher_order_test.go`
- Test: `internal/service/voucher_order_test.go`

- [ ] **Step 1: Write the failing publisher tests**

Add tests in `internal/service/voucher_order_test.go` that lock down the important behaviors by isolating MQ sending behind a tiny function variable or interface.

Expected test cases:

```go
func TestSeckillVoucherByRedisAndRocketMQ_RollsBackReservationWhenSendFails(t *testing.T)
func TestSeckillVoucherByRedisAndRocketMQ_ReturnsOrderIDWhenSendSucceeds(t *testing.T)
```

Introduce the minimum seam needed for TDD, for example:

```go
type voucherOrderMQProducer interface {
	SendSync(ctx context.Context, msgs ...*primitive.Message) (*primitive.SendResult, error)
}

var voucherOrderProducer voucherOrderMQProducer
var rollbackReservationFn = rollbackSeckillReservation
```

The failing test should assert:

- send failure returns `dto.Fail("系统繁忙，请稍后再试！")`
- rollback function is invoked with the same `voucherId` and `userId`
- successful send returns `dto.OkWithData(orderId)`

- [ ] **Step 2: Run the focused service tests and watch them fail for the right reason**

Run: `go test ./internal/service -run 'TestSeckillVoucherByRedisAndRocketMQ_(RollsBackReservationWhenSendFails|ReturnsOrderIDWhenSendSucceeds)'`
Expected: FAIL because the RocketMQ publisher path and test seam do not exist yet.

- [ ] **Step 3: Implement the minimal publisher replacement**

In `internal/service/voucher_order.go`:

- rename `SeckillVoucherByRedisAndKafka` to `SeckillVoucherByRedisAndRocketMQ`
- update `internal/handler/voucher_order.go` to call the new method name so the HTTP path continues to compile and route requests correctly
- keep the existing Lua pre-deduct and duplicate-order checks unchanged
- JSON-encode the same `entity.VoucherOrder`
- build a RocketMQ message:

```go
msg := &primitive.Message{
	Topic: config.GlobalConfig.RocketMQ.Topic,
	Body:  orderBytes,
	Keys:  []string{strconv.FormatUint(userId, 10), strconv.FormatUint(orderId, 10)},
}
```

- call `voucherOrderProducer.SendSync`
- on send error, log it, call `rollbackReservationFn(c, voucherId, userId)`, and return the current busy error result

Keep the change minimal. Do not refactor unrelated voucher-order logic.

- [ ] **Step 4: Run the focused service tests again**

Run: `go test ./internal/service -run 'TestSeckillVoucherByRedisAndRocketMQ_(RollsBackReservationWhenSendFails|ReturnsOrderIDWhenSendSucceeds)'`
Expected: PASS.

- [ ] **Step 5: Run a wider regression slice for voucher-order code**

Run: `go test ./internal/service -run 'TestSeckillVoucherByRedisAndRocketMQ|Test.*VoucherOrder'`
Expected: PASS, or no additional matching tests beyond the new ones.

- [ ] **Step 6: Commit**

```bash
git add internal/service/voucher_order.go internal/handler/voucher_order.go internal/service/voucher_order_test.go
git commit -m "refactor: publish voucher orders with rocketmq"
```

### Task 3: Replace Voucher Order Consumption And Retry Semantics

**Files:**
- Modify: `internal/service/voucher_order.go`
- Modify: `internal/global/rocketmq.go`
- Modify: `cmd/api/main.go`
- Modify: `internal/service/voucher_order_test.go`
- Test: `internal/service/voucher_order_test.go`

- [ ] **Step 1: Write the failing consumer behavior tests**

Add focused tests for the message handler logic before wiring the real RocketMQ consumer:

```go
func TestConsumeVoucherOrderMessage_ReturnsRetryLaterWhenHandleFails(t *testing.T)
func TestConsumeVoucherOrderMessage_ReturnsSuccessWhenHandleSucceeds(t *testing.T)
func TestConsumeVoucherOrderMessage_SkipsBadJSON(t *testing.T)
```

Extract a small helper to make this testable without booting the real MQ client:

```go
func consumeVoucherOrderMessage(
	ctx context.Context,
	handle func(order *entity.VoucherOrder) error,
	body []byte,
) consumer.ConsumeResult
```

Assertions:

- bad JSON returns `consumer.ConsumeSuccess`
- business error returns `consumer.ConsumeRetryLater`
- successful handling returns `consumer.ConsumeSuccess`

- [ ] **Step 2: Run the focused consumer tests to verify red**

Run: `go test ./internal/service -run 'TestConsumeVoucherOrderMessage_(ReturnsRetryLaterWhenHandleFails|ReturnsSuccessWhenHandleSucceeds|SkipsBadJSON)'`
Expected: FAIL because the helper and RocketMQ consume semantics are not implemented yet.

- [ ] **Step 3: Implement the minimal consumer replacement**

Update `internal/service/voucher_order.go` so `StartVoucherOrderConsumer`:

- does **not** create or start a RocketMQ consumer; ownership stays in `internal/global`
- assumes `main` has already called `global.InitRocketMQConsumer()` and stored the ready consumer in `global.RocketMQConsumer`
- removes the old package `init()` auto-start path so `go test` does not attempt a real MQ connection during package initialization
- subscribes to `config.GlobalConfig.RocketMQ.Topic`
- starts consumption through the already-created `global.RocketMQConsumer`
- delegates body handling to `consumeVoucherOrderMessage`

Target shape:

```go
result, err := global.RocketMQConsumer.Subscribe(
	config.GlobalConfig.RocketMQ.Topic,
	consumer.MessageSelector{},
	func(ctx context.Context, msgs ...*primitive.MessageExt) (consumer.ConsumeResult, error) {
		for _, msg := range msgs {
			if result := consumeVoucherOrderMessage(ctx, service.handleVoucherOrder, msg.Body); result != consumer.ConsumeSuccess {
				return result, nil
			}
		}
		return consumer.ConsumeSuccess, nil
	},
)
```

Inside `consumeVoucherOrderMessage`:

- unmarshal `entity.VoucherOrder`
- skip bad JSON with an error log and `consumer.ConsumeSuccess`
- call `handleVoucherOrder`
- return `consumer.ConsumeRetryLater` on business failure

Also add a safe consumer shutdown function in `internal/global/rocketmq.go`, and update `cmd/api/main.go` to call it during graceful shutdown.

The ownership split must be explicit in code:

- `internal/global`: create/start/shutdown producer and consumer
- `internal/service`: register voucher-order subscription callback and expose `StartVoucherOrderConsumer`
- `cmd/api/main.go`: call startup in the declared order and shutdown in reverse order

- [ ] **Step 4: Run the focused consumer tests again**

Run: `go test ./internal/service -run 'TestConsumeVoucherOrderMessage_(ReturnsRetryLaterWhenHandleFails|ReturnsSuccessWhenHandleSucceeds|SkipsBadJSON)'`
Expected: PASS.

- [ ] **Step 5: Run the service package tests to check combined producer/consumer behavior**

Run: `go test ./internal/service`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add internal/service/voucher_order.go internal/service/voucher_order_test.go internal/global/rocketmq.go cmd/api/main.go
git commit -m "refactor: consume voucher orders with rocketmq"
```

### Task 4: Update Documentation And Run Full Regression

**Files:**
- Modify: `README.md`
- Modify: `docs/superpowers/specs/2026-03-29-rocketmq-migration-design.md` (only if implementation reality diverged from spec)
- Test: `go test ./...`

- [ ] **Step 1: Write the failing documentation checklist**

List the docs that must stop mentioning Kafka and must explain RocketMQ setup instead:

- runtime configuration keys
- local deployment dependencies
- topic/group troubleshooting notes
- graceful shutdown behavior if documented

- [ ] **Step 2: Search for stale Kafka references**

Run: `rg -n 'Kafka|kafka|broker|group_id' README.md config internal`
Expected: FAIL in the sense that references still exist and must be updated or intentionally retained.

- [ ] **Step 3: Update README to match the implemented RocketMQ setup**

Ensure the README documents:

- `rocketmq.name_servers`
- `rocketmq.topic`
- `rocketmq.producer_group`
- `rocketmq.consumer_group`
- local RocketMQ dependency expectations
- revised troubleshooting guidance for producer send failure and consumer retry issues

- [ ] **Step 4: Run the full regression suite**

Run: `go test ./...`
Expected: PASS.

- [ ] **Step 5: Confirm formatting is clean**

Run: `gofmt -w config/config.go cmd/api/main.go internal/global/rocketmq.go internal/service/voucher_order.go internal/service/voucher_order_test.go`
Expected: no output; files rewritten in standard Go format.

- [ ] **Step 6: Re-run the full regression after formatting**

Run: `go test ./...`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add README.md config/config.go cmd/api/main.go internal/global/rocketmq.go internal/service/voucher_order.go internal/service/voucher_order_test.go go.mod go.sum
git commit -m "docs: update mq setup to rocketmq"
```
