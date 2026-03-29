# RocketMQ Compose Stability Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the local RocketMQ stack start reliably with `docker compose up -d` and ensure `voucher-order-topic` exists automatically.

**Architecture:** Keep the existing RocketMQ image and network layout. Add a small JVM heap override to the broker so it starts in constrained local environments, then add a one-shot init container that waits for namesrv and broker health before creating the topic with `mqadmin`.

**Tech Stack:** Docker Compose, Apache RocketMQ 5.3.2

---

### Task 1: Stabilize RocketMQ startup and auto-create topic

**Files:**
- Modify: `docker-compose.yaml`

- [ ] **Step 1: Apply the minimal compose change**

Add `JAVA_OPT_EXT=-Xms256m -Xmx256m -Xmn128m` to `rocketmq-broker`, and add a `rocketmq-init` service that depends on both RocketMQ healthchecks and runs `mqadmin updateTopic -n rocketmq-namesrv:9876 -c DefaultCluster -t voucher-order-topic -r 4 -w 4`.

- [ ] **Step 2: Verify the stack starts cleanly**

Run: `docker compose up -d`

Expected: `hmdp-rocketmq-namesrv`, `hmdp-rocketmq-broker`, and `hmdp-rocketmq-init` all start without restart loops.

- [ ] **Step 3: Verify the topic exists**

Run: `docker exec hmdp-rocketmq-broker bash -c "cd /home/rocketmq/rocketmq-5.3.2/bin && ./mqadmin topicList -n rocketmq-namesrv:9876 | grep voucher-order-topic"`

Expected: `voucher-order-topic`
