# Redislock Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the repository's distributed locking implementations with `github.com/bsm/redislock` and update voucher order flows to use a single lock abstraction.

**Architecture:** Keep the existing `internal/util.Lock` interface as the application boundary, but back it with a `redislock` client. Remove the self-managed Redisson-style watchdog implementation and the direct `redsync` usage in `voucher_order.go` so all distributed locking behavior is routed through one utility.

**Tech Stack:** Go, go-redis/v9, github.com/bsm/redislock, Go testing

---

### Task 1: Add a failing lock behavior test

**Files:**
- Create: `internal/util/redis_lock_test.go`
- Test: `internal/util/redis_lock_test.go`

- [ ] **Step 1: Write the failing test**
- [ ] **Step 2: Run `go test ./internal/util` with local `GOCACHE` and verify it fails for the missing/new lock behavior**
- [ ] **Step 3: Keep the test focused on lock exclusivity and release semantics**

### Task 2: Replace the lock implementation

**Files:**
- Create: `internal/util/redis_lock.go`
- Modify: `internal/util/lock.go`
- Delete: `internal/util/redisson_lock.go`
- Delete: `internal/util/simple_redis_lock.go`

- [ ] **Step 1: Add a `redislock`-backed implementation that satisfies `Lock`**
- [ ] **Step 2: Preserve the existing `TryLock(timeoutSec)` / `Unlock()` contract**
- [ ] **Step 3: Re-run `go test ./internal/util` and verify the new test passes**

### Task 3: Migrate voucher order flows and dependencies

**Files:**
- Modify: `internal/service/voucher_order.go`
- Modify: `go.mod`
- Modify: `go.sum`

- [ ] **Step 1: Remove `redsync` initialization and all direct `redsync` locking**
- [ ] **Step 2: Route voucher order locking through the unified util lock**
- [ ] **Step 3: Re-run targeted tests, then `go test ./...` with local `GOCACHE`**
- [ ] **Step 4: Commit with a focused message once verification is green**
