import assert from 'node:assert/strict';
import test from 'node:test';

import {
  buildSeckillScenario,
  limitTokenPool,
  parsePositiveInt,
} from './seckill-config.mjs';

test('buildSeckillScenario uses per-vu-iterations for same-time seckill', () => {
  assert.deepEqual(buildSeckillScenario(1000), {
    executor: 'per-vu-iterations',
    vus: 1000,
    iterations: 1,
    maxDuration: '30m',
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
