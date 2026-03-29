package util

import (
	"context"
	"testing"

	"github.com/alicebob/miniredis/v2"
	"github.com/redis/go-redis/v9"
)

func TestRedisLockPreventsDuplicateAcquireUntilRelease(t *testing.T) {
	ctx := context.Background()
	server, err := miniredis.Run()
	if err != nil {
		t.Fatalf("start miniredis: %v", err)
	}
	defer server.Close()

	client := redis.NewClient(&redis.Options{Addr: server.Addr()})
	defer client.Close()

	first := NewRedisLock(ctx, "order:1", client)
	if !first.TryLock(5) {
		t.Fatal("expected first lock acquisition to succeed")
	}

	second := NewRedisLock(ctx, "order:1", client)
	if second.TryLock(5) {
		t.Fatal("expected second lock acquisition to fail while first lock is held")
	}

	if err := first.Unlock(); err != nil {
		t.Fatalf("unlock first lock: %v", err)
	}

	if !second.TryLock(5) {
		t.Fatal("expected second lock acquisition to succeed after release")
	}
}
