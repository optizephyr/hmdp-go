# JMeter A/B Benchmark Report

## 1. Run Metadata

- Date:
- Environment (host, cpu, memory):
- Service version/commit:
- MySQL/Redis/RocketMQ version:
- Base URL:
- Voucher ID / stock (seckill):

## 2. Test Strategy

- Sequential A/B only: run A first, reset environment, run B.
- Stage rhythm: 60s ramp + 180s hold + 30s cooldown.
- Read stages (users): 100 / 300 / 600.
- Seckill stages (users): 500 / 1000 / 2000.

## 3. Read Benchmark (A: direct DB, B: cache)

| Stage | Users | A QPS | B QPS | Delta QPS | A Avg(ms) | B Avg(ms) | A P95(ms) | B P95(ms) | A P99(ms) | B P99(ms) | A Err% | B Err% |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 | 100 |  |  |  |  |  |  |  |  |  |  |  |
| 2 | 300 |  |  |  |  |  |  |  |  |  |  |  |
| 3 | 600 |  |  |  |  |  |  |  |  |  |  |  |

## 4. Seckill Benchmark (A: tx baseline, B: Redis+Lua+MQ)

| Stage | Users | A QPS | B QPS | Delta QPS | A Avg(ms) | B Avg(ms) | A P95(ms) | B P95(ms) | A P99(ms) | B P99(ms) | A Err% | B Err% |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 | 500 |  |  |  |  |  |  |  |  |  |  |  |
| 2 | 1000 |  |  |  |  |  |  |  |  |  |  |  |
| 3 | 2000 |  |  |  |  |  |  |  |  |  |  |  |

## 5. Seckill Consistency Checks

### A Run

- order_count:
- distinct_user_count:
- duplicate_count (must be 0):
- expected_remaining_stock:
- actual_remaining_stock:
- oversell (must be 0):

### B Run

- order_count:
- distinct_user_count:
- duplicate_count (must be 0):
- expected_remaining_stock:
- actual_remaining_stock:
- oversell (must be 0):

## 6. Conclusion

- Read path bottleneck stage:
- Seckill bottleneck stage:
- Which variant is better and why:
- Risks/notes (e.g., error spikes, long-tail RT):
