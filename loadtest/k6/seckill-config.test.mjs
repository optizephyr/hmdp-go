import assert from 'node:assert/strict';
import test from 'node:test';

import {
  buildSeckillScenario,
  limitTokenPool,
  parsePositiveInt,
  pickTokenForRequest,
} from './seckill-config.mjs';

test('buildSeckillScenario uses constant-arrival-rate for seckill qps', () => {
  assert.deepEqual(buildSeckillScenario(1000), {
    executor: 'constant-arrival-rate',
    rate: 1000,
    timeUnit: '1s',
    duration: '1m',
    preAllocatedVUs: 1000,
    maxVUs: 2000,
    gracefulStop: '0s',
  });
});

test('limitTokenPool keeps the requested unique users', () => {
  const pool = [
    { userId: '1', token: 't1' },
    { userId: '2', token: 't2' },
    { userId: '3', token: 't3' },
  ];

  assert.deepEqual(limitTokenPool(pool, 2), pool.slice(0, 2));
});

test('parsePositiveInt falls back on invalid values', () => {
  assert.equal(parsePositiveInt('2000', 1000), 2000);
  assert.equal(parsePositiveInt('0', 1000), 1000);
  assert.equal(parsePositiveInt('-1', 1000), 1000);
  assert.equal(parsePositiveInt('abc', 1000), 1000);
});

test('pickTokenForRequest rotates users across requests', () => {
  const pool = [
    { userId: '1', token: 't1' },
    { userId: '2', token: 't2' },
    { userId: '3', token: 't3' },
  ];

  assert.deepEqual(pickTokenForRequest(pool, 1, 0), pool[0]);
  assert.deepEqual(pickTokenForRequest(pool, 1, 1), pool[1]);
  assert.deepEqual(pickTokenForRequest(pool, 2, 0), pool[1]);
});
