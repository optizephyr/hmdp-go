# k6 秒杀远程运行 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Allow the existing seckill benchmark flow to run from a local laptop against a remote service without requiring local MySQL or Redis containers.

**Architecture:** Make the Go config and benchmark shell script honor explicit remote host/env overrides. The benchmark script will talk to MySQL/Redis over TCP instead of `docker exec`, while k6 still targets the remote HTTP base URL.

**Tech Stack:** Go, Bash, MySQL client, redis-cli, k6

---

### Task 1: Add remote connection overrides

**Files:**
- Modify: `config/config.go`
- Modify: `internal/global/mysql.go`
- Modify: `internal/global/redis.go`

- [ ] **Step 1: Add env overrides for MySQL/Redis host and port**
- [ ] **Step 2: Normalize host/port assembly so config values work with or without leading colons**
- [ ] **Step 3: Verify the app still starts with the default local config**

### Task 2: Make the seckill benchmark shell script network-based

**Files:**
- Modify: `loadtest/k6/run-seckill-benchmark.sh`

- [ ] **Step 1: Replace `docker exec` reset/verify calls with direct `mysql` and `redis-cli` commands**
- [ ] **Step 2: Forward the same env overrides into the token-generation `go test` step**
- [ ] **Step 3: Add clear help text for running against remote services**

### Task 3: Update docs

**Files:**
- Modify: `loadtest/k6/README.md`
- Modify: `README.md`

- [ ] **Step 1: Document the remote MySQL/Redis env vars**
- [ ] **Step 2: Document the local-k6/remote-service command sequence**
- [ ] **Step 3: Verify the examples match the final script flags and env names**

### Task 4: Verify the flow

**Files:**
- None

- [ ] **Step 1: Run a dry-run of the token generation step with remote env vars set**
- [ ] **Step 2: Run the benchmark script in skip/remote mode**
- [ ] **Step 3: Confirm the script no longer depends on local MySQL/Redis containers**
