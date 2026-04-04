package service

import (
	"context"
	"encoding/json"
	"errors"
	"strconv"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/amemiya02/hmdp-go/config"
	"github.com/amemiya02/hmdp-go/internal/constant"
	"github.com/amemiya02/hmdp-go/internal/global"
	"github.com/amemiya02/hmdp-go/internal/model/dto"
	"github.com/amemiya02/hmdp-go/internal/model/entity"
	"github.com/apache/rocketmq-client-go/v2/consumer"
	"github.com/apache/rocketmq-client-go/v2/primitive"
)

type testVoucherOrderProducer struct {
	sendFn func(ctx context.Context, msgs ...*primitive.Message) (*primitive.SendResult, error)
}

func (p *testVoucherOrderProducer) SendSync(ctx context.Context, msgs ...*primitive.Message) (*primitive.SendResult, error) {
	if p.sendFn != nil {
		return p.sendFn(ctx, msgs...)
	}
	return &primitive.SendResult{Status: primitive.SendOK}, nil
}

type testRocketMQConsumer struct {
	startErr     error
	subscribeErr error
}

func (c *testRocketMQConsumer) Start() error {
	return c.startErr
}

func (c *testRocketMQConsumer) Subscribe(topic string, selector consumer.MessageSelector, callback func(context.Context, ...*primitive.MessageExt) (consumer.ConsumeResult, error)) error {
	return c.subscribeErr
}

func (c *testRocketMQConsumer) Unsubscribe(topic string) error {
	return nil
}

func (c *testRocketMQConsumer) Shutdown() error {
	return nil
}

func testVoucherOrderContext(userID uint64) context.Context {
	return context.WithValue(context.Background(), constant.ContextUserKey, &dto.UserDTO{ID: userID})
}

func resetVoucherOrderConsumerState() {
	startVoucherOrderConsumerOnce = sync.Once{}
	startVoucherOrderTaskOnce = sync.Once{}
	stopVoucherOrderConsumerOnce = sync.Once{}
	voucherOrderConsumerCancel = nil
}

func prepareVoucherOrderSeckillState(t *testing.T, voucherID uint64, stock int64) {
	t.Helper()

	ctx := context.Background()
	stockKey := constant.SeckillStockKey + strconv.FormatUint(voucherID, 10)
	orderKey := "seckill:order:" + strconv.FormatUint(voucherID, 10)

	if err := global.RedisClient.Set(ctx, stockKey, stock, 0).Err(); err != nil {
		t.Fatalf("set stock failed: %v", err)
	}
	if err := global.RedisClient.Del(ctx, orderKey).Err(); err != nil {
		t.Fatalf("clear order set failed: %v", err)
	}

	t.Cleanup(func() {
		_, _ = global.RedisClient.Del(ctx, stockKey, orderKey).Result()
	})
}

func TestSeckillVoucherByRedisAndRocketMQ_RollsBackReservationWhenSendFails(t *testing.T) {
	const (
		userID    = uint64(10001)
		voucherID = uint64(20001)
	)

	prepareVoucherOrderSeckillState(t, voucherID, 1)

	oldProducer := voucherOrderProducer
	oldRollback := rollbackReservationFn
	t.Cleanup(func() {
		voucherOrderProducer = oldProducer
		rollbackReservationFn = oldRollback
	})

	producerCalls := 0
	voucherOrderProducer = &testVoucherOrderProducer{
		sendFn: func(ctx context.Context, msgs ...*primitive.Message) (*primitive.SendResult, error) {
			producerCalls++
			if len(msgs) != 1 {
				t.Fatalf("expected 1 message, got %d", len(msgs))
			}
			if msgs[0].Topic != config.GlobalConfig.RocketMQ.Topic {
				t.Fatalf("unexpected topic: %s", msgs[0].Topic)
			}
			return nil, errors.New("boom")
		},
	}

	var rollbackCalled bool
	var gotVoucherID uint64
	var gotUserID uint64
	rollbackReservationFn = func(ctx context.Context, voucherId, userId uint64) {
		rollbackCalled = true
		gotVoucherID = voucherId
		gotUserID = userId
	}

	result := NewVoucherOrderService().SeckillVoucherByRedisAndRocketMQ(testVoucherOrderContext(userID), voucherID)

	if result.Success {
		t.Fatalf("expected failure, got success: %#v", result)
	}
	if result.ErrorMsg != "系统繁忙，请稍后再试！" {
		t.Fatalf("unexpected error msg: %s", result.ErrorMsg)
	}
	if producerCalls != 1 {
		t.Fatalf("expected producer to be called once, got %d", producerCalls)
	}
	if !rollbackCalled {
		t.Fatal("expected rollbackReservationFn to be called")
	}
	if gotVoucherID != voucherID || gotUserID != userID {
		t.Fatalf("rollback called with wrong ids: got voucher=%d user=%d", gotVoucherID, gotUserID)
	}
}

func TestStartVoucherOrderConsumer_ReturnsSubscribeError(t *testing.T) {
	oldConsumer := global.RocketMQConsumer
	defer func() {
		global.RocketMQConsumer = oldConsumer
		resetVoucherOrderConsumerState()
	}()

	global.RocketMQConsumer = &testRocketMQConsumer{subscribeErr: errors.New("subscribe failed")}
	resetVoucherOrderConsumerState()

	err := StartVoucherOrderConsumer(context.Background())
	if err == nil {
		t.Fatal("expected start error, got nil")
	}
	if !strings.Contains(err.Error(), "subscribe failed") {
		t.Fatalf("unexpected error: %v", err)
	}
}

func TestSeckillVoucherByRedisAndRocketMQ_ReturnsOrderIDWhenSendSucceeds(t *testing.T) {
	const (
		userID    = uint64(10002)
		voucherID = uint64(20002)
	)

	prepareVoucherOrderSeckillState(t, voucherID, 1)

	oldProducer := voucherOrderProducer
	oldRollback := rollbackReservationFn
	t.Cleanup(func() {
		voucherOrderProducer = oldProducer
		rollbackReservationFn = oldRollback
	})

	var capturedMsg *primitive.Message
	voucherOrderProducer = &testVoucherOrderProducer{
		sendFn: func(ctx context.Context, msgs ...*primitive.Message) (*primitive.SendResult, error) {
			if len(msgs) != 1 {
				t.Fatalf("expected 1 message, got %d", len(msgs))
			}
			if msgs[0].Topic != config.GlobalConfig.RocketMQ.Topic {
				t.Fatalf("unexpected topic: %s", msgs[0].Topic)
			}
			capturedMsg = msgs[0]
			return &primitive.SendResult{Status: primitive.SendOK}, nil
		},
	}
	rollbackReservationFn = func(ctx context.Context, voucherId, userId uint64) {
		t.Fatalf("rollback should not be called on success")
	}

	result := NewVoucherOrderService().SeckillVoucherByRedisAndRocketMQ(testVoucherOrderContext(userID), voucherID)

	if !result.Success {
		t.Fatalf("expected success, got %#v", result)
	}

	orderID, ok := result.Data.(int64)
	if !ok {
		t.Fatalf("expected int64 order id, got %T", result.Data)
	}
	if orderID == 0 {
		t.Fatal("expected non-zero order id")
	}
	if capturedMsg == nil {
		t.Fatal("expected message to be captured")
	}

	if got := capturedMsg.GetKeys(); got != strings.Join([]string{
		strconv.FormatUint(userID, 10),
		strconv.FormatInt(orderID, 10),
	}, " ") {
		t.Fatalf("unexpected message keys: %s", got)
	}

	var order entity.VoucherOrder
	if err := json.Unmarshal(capturedMsg.Body, &order); err != nil {
		t.Fatalf("unmarshal message body failed: %v", err)
	}
	if order.ID != orderID {
		t.Fatalf("order id mismatch: got %d want %d", order.ID, orderID)
	}
	if order.UserID != userID {
		t.Fatalf("user id mismatch: got %d want %d", order.UserID, userID)
	}
	if order.VoucherID != voucherID {
		t.Fatalf("voucher id mismatch: got %d want %d", order.VoucherID, voucherID)
	}

	orderKey := "seckill:order:" + strconv.FormatUint(voucherID, 10)
	stockKey := constant.SeckillStockKey + strconv.FormatUint(voucherID, 10)

	orderExists, err := global.RedisClient.SIsMember(context.Background(), orderKey, userID).Result()
	if err != nil {
		t.Fatalf("check order set failed: %v", err)
	}
	if !orderExists {
		t.Fatal("expected reservation to remain after successful send")
	}

	stock, err := global.RedisClient.Get(context.Background(), stockKey).Int64()
	if err != nil {
		t.Fatalf("read stock failed: %v", err)
	}
	if stock != 0 {
		t.Fatalf("expected stock to be reserved once, got %d", stock)
	}
}

func TestSeckillVoucherByRedisAndRocketMQ_SkipsRocketMQWhenDisabled(t *testing.T) {
	const (
		userID    = uint64(10003)
		voucherID = uint64(20003)
	)

	prepareVoucherOrderSeckillState(t, voucherID, 1)
	t.Setenv("K6_DISABLE_ROCKETMQ_SEND", "1")

	oldProducer := voucherOrderProducer
	t.Cleanup(func() {
		voucherOrderProducer = oldProducer
	})
	voucherOrderProducer = &testVoucherOrderProducer{
		sendFn: func(ctx context.Context, msgs ...*primitive.Message) (*primitive.SendResult, error) {
			t.Fatal("SendSync should not be called when RocketMQ is disabled")
			return nil, nil
		},
	}

	result := NewVoucherOrderService().SeckillVoucherByRedisAndRocketMQ(testVoucherOrderContext(userID), voucherID)

	if !result.Success {
		t.Fatalf("expected success, got %#v", result)
	}
	if _, ok := result.Data.(int64); !ok {
		t.Fatalf("expected int64 order id, got %T", result.Data)
	}
}

func TestHandleVoucherOrderPersistsOrderAndDeductsStock(t *testing.T) {
	ctx := context.Background()
	service := NewVoucherOrderService()

	const (
		userID    = uint64(20001)
		voucherID = uint64(30001)
		orderID   = int64(3000100001)
	)

	if err := global.Db.WithContext(ctx).Where("voucher_id = ?", voucherID).Delete(&entity.SeckillVoucher{}).Error; err != nil {
		t.Fatalf("cleanup seckill voucher failed: %v", err)
	}
	if err := global.Db.WithContext(ctx).Where("id = ?", orderID).Delete(&entity.VoucherOrder{}).Error; err != nil {
		t.Fatalf("cleanup voucher order failed: %v", err)
	}
	t.Cleanup(func() {
		_ = global.Db.WithContext(ctx).Where("voucher_id = ?", voucherID).Delete(&entity.SeckillVoucher{}).Error
		_ = global.Db.WithContext(ctx).Where("id = ?", orderID).Delete(&entity.VoucherOrder{}).Error
	})

	now := time.Now()
	if err := global.Db.WithContext(ctx).Create(&entity.SeckillVoucher{
		VoucherID:  voucherID,
		Stock:      1,
		BeginTime:  now.Add(-time.Hour),
		EndTime:    now.Add(time.Hour),
		UpdateTime: now,
	}).Error; err != nil {
		t.Fatalf("prepare seckill voucher failed: %v", err)
	}

	order := &entity.VoucherOrder{
		ID:        orderID,
		UserID:    userID,
		VoucherID: voucherID,
	}

	if err := service.handleVoucherOrder(order); err != nil {
		t.Fatalf("handleVoucherOrder failed: %v", err)
	}

	var orderCount int64
	if err := global.Db.WithContext(ctx).Model(&entity.VoucherOrder{}).Where("id = ?", orderID).Count(&orderCount).Error; err != nil {
		t.Fatalf("count inserted order failed: %v", err)
	}
	if orderCount != 1 {
		t.Fatalf("expected 1 inserted order, got %d", orderCount)
	}

	var stock int
	if err := global.Db.WithContext(ctx).Model(&entity.SeckillVoucher{}).Select("stock").Where("voucher_id = ?", voucherID).Scan(&stock).Error; err != nil {
		t.Fatalf("read stock failed: %v", err)
	}
	if stock != 0 {
		t.Fatalf("expected stock to be deducted to 0, got %d", stock)
	}
}
