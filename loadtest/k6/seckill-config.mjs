export function parsePositiveInt(rawValue, fallback) {
  const parsed = Number.parseInt(rawValue, 10);
  if (!Number.isInteger(parsed) || parsed <= 0) {
    return fallback;
  }

  return parsed;
}

export function buildSeckillScenario(vus) {
  return {
    executor: 'per-vu-iterations',
    vus,
    iterations: 1,
    maxDuration: '30m',
    gracefulStop: '0s',
  };
}

export function limitTokenPool(pool, count) {
  if (!Array.isArray(pool)) {
    throw new TypeError('token pool must be an array');
  }

  if (pool.length < count) {
    throw new Error(`token pool needs at least ${count} users, got ${pool.length}`);
  }

  return pool.slice(0, count);
}

export function pickTokenForVu(pool, vu) {
  if (!Array.isArray(pool)) {
    throw new TypeError('token pool must be an array');
  }

  const index = vu - 1;
  if (index < 0 || index >= pool.length) {
    throw new Error(`VU ${vu} is outside the token pool of size ${pool.length}`);
  }

  return pool[index];
}
