export function parsePositiveInt(rawValue, fallback) {
  const parsed = Number.parseInt(rawValue, 10);
  if (!Number.isInteger(parsed) || parsed <= 0) {
    return fallback;
  }

  return parsed;
}

export function buildSeckillScenario(rate, duration = '1m') {
  return {
    executor: 'constant-arrival-rate',
    rate,
    timeUnit: '1s',
    duration,
    preAllocatedVUs: rate,
    maxVUs: rate * 2,
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

export function pickTokenForRequest(pool, vu, iter) {
  if (!Array.isArray(pool)) {
    throw new TypeError('token pool must be an array');
  }

  const index = (vu - 1 + iter) % pool.length;
  if (index < 0 || index >= pool.length) {
    throw new Error(`request index ${index} is outside the token pool of size ${pool.length}`);
  }

  return pool[index];
}
