package service

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/amemiya02/hmdp-go/internal/model/entity"
)

func withShopQueryHooks(t *testing.T) {
	t.Helper()

	oldL1Get := queryShopByIDL1Get
	oldL1Set := queryShopByIDL1Set
	oldRemote := queryShopByIDRemote

	t.Cleanup(func() {
		queryShopByIDL1Get = oldL1Get
		queryShopByIDL1Set = oldL1Set
		queryShopByIDRemote = oldRemote
	})
}

func TestQueryShopById_L1HitBypassesRemotePath(t *testing.T) {
	withShopQueryHooks(t)

	l1Shop := &entity.Shop{ID: 1, Name: "l1-shop"}
	remoteCalled := 0

	queryShopByIDL1Get = func(key string) (*entity.Shop, error) {
		return l1Shop, nil
	}
	queryShopByIDRemote = func(ctx context.Context, key string, lockKey string, ttl time.Duration, fallback func() (*entity.Shop, error)) (*entity.Shop, error) {
		remoteCalled++
		return &entity.Shop{ID: 1, Name: "remote-shop"}, nil
	}

	result := NewShopService().QueryShopById(context.Background(), 1)
	if !result.Success {
		t.Fatalf("expected success, got failure: %#v", result)
	}

	shop, ok := result.Data.(*entity.Shop)
	if !ok {
		t.Fatalf("expected *entity.Shop, got %T", result.Data)
	}
	if shop.Name != "l1-shop" {
		t.Fatalf("expected L1 shop data, got %q", shop.Name)
	}
	if remoteCalled != 0 {
		t.Fatalf("expected remote path to be bypassed on L1 hit, got %d calls", remoteCalled)
	}
}

func TestQueryShopById_L1MissCallsRemoteAndBackfillsL1(t *testing.T) {
	withShopQueryHooks(t)

	remoteShop := &entity.Shop{ID: 2, Name: "remote-shop"}
	remoteCalled := 0
	l1SetCalled := 0

	queryShopByIDL1Get = func(key string) (*entity.Shop, error) {
		return nil, nil
	}
	queryShopByIDL1Set = func(key string, shop *entity.Shop) {
		l1SetCalled++
	}
	queryShopByIDRemote = func(ctx context.Context, key string, lockKey string, ttl time.Duration, fallback func() (*entity.Shop, error)) (*entity.Shop, error) {
		remoteCalled++
		return remoteShop, nil
	}

	result := NewShopService().QueryShopById(context.Background(), 2)
	if !result.Success {
		t.Fatalf("expected success, got failure: %#v", result)
	}

	if remoteCalled != 1 {
		t.Fatalf("expected remote path to be called once, got %d", remoteCalled)
	}
	if l1SetCalled != 1 {
		t.Fatalf("expected L1 to be backfilled once, got %d", l1SetCalled)
	}
}

func TestQueryShopById_L1ReadErrorDegradesToRemotePath(t *testing.T) {
	withShopQueryHooks(t)

	l1GetCalled := 0
	remoteCalled := 0

	queryShopByIDL1Get = func(key string) (*entity.Shop, error) {
		l1GetCalled++
		return nil, errors.New("l1 read failed")
	}
	queryShopByIDRemote = func(ctx context.Context, key string, lockKey string, ttl time.Duration, fallback func() (*entity.Shop, error)) (*entity.Shop, error) {
		remoteCalled++
		return &entity.Shop{ID: 3, Name: "remote-shop"}, nil
	}

	result := NewShopService().QueryShopById(context.Background(), 3)
	if !result.Success {
		t.Fatalf("expected remote fallback success, got failure: %#v", result)
	}

	if l1GetCalled != 1 {
		t.Fatalf("expected L1 read attempt once before degrade, got %d", l1GetCalled)
	}
	if remoteCalled != 1 {
		t.Fatalf("expected remote path once after L1 read error, got %d", remoteCalled)
	}
}
