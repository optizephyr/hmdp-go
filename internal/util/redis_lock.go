package util

import (
	"context"
	"errors"
	"time"

	"github.com/bsm/redislock"
	"github.com/redis/go-redis/v9"
)

var _ Lock = (*RedisLock)(nil)

const (
	keyPrefix     = "lock:"
	retryInterval = 50 * time.Millisecond
)

type RedisLock struct {
	ctx        context.Context
	key        string
	locker     *redislock.Client
	lock       *redislock.Lock
	obtainOpts *redislock.Options
}

func NewRedisLock(ctx context.Context, name string, client *redis.Client) Lock {
	return NewRedisLockWithWait(ctx, name, client, 0)
}

func NewRedisLockWithWait(ctx context.Context, name string, client *redis.Client, wait time.Duration) Lock {
	return &RedisLock{
		ctx:        ctx,
		key:        keyPrefix + name,
		locker:     redislock.New(client),
		obtainOpts: buildRedisLockOptions(wait),
	}
}

func buildRedisLockOptions(wait time.Duration) *redislock.Options {
	if wait <= 0 {
		return nil
	}

	retries := int(wait / retryInterval)
	if retries < 1 {
		retries = 1
	}

	return &redislock.Options{
		RetryStrategy: redislock.LimitRetry(redislock.LinearBackoff(retryInterval), retries),
	}
}

func (l *RedisLock) TryLock(timeoutSec uint64) bool {
	lock, err := l.locker.Obtain(l.ctx, l.key, time.Duration(timeoutSec)*time.Second, l.obtainOpts)
	if err != nil {
		return false
	}

	l.lock = lock
	return true
}

func (l *RedisLock) Unlock() error {
	if l.lock == nil {
		return redislock.ErrLockNotHeld
	}

	err := l.lock.Release(l.ctx)
	if err == nil || errors.Is(err, redislock.ErrLockNotHeld) {
		l.lock = nil
	}
	return err
}
