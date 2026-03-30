import http from 'k6/http';
import { check, fail } from 'k6';
import { Counter, Rate } from 'k6/metrics';
import {
  buildSeckillScenario,
  limitTokenPool,
  parsePositiveInt,
  pickTokenForRequest,
} from './seckill-config.mjs';

const baseUrl = __ENV.BASE_URL || 'http://127.0.0.1:8081';
const benchmarkQps = parsePositiveInt(__ENV.BENCHMARK_QPS, 1000);
const benchmarkDuration = __ENV.BENCHMARK_DURATION || '1m';
const tokenCount = parsePositiveInt(__ENV.BENCHMARK_TOKEN_COUNT, benchmarkQps);
const rawTokens = open('./data/token-users.csv');
const fixtureVoucher = JSON.parse(open('./data/fixture-voucher.json'));

const systemErrors = new Rate('system_errors');
const stockRejections = new Counter('stock_rejections');
const duplicateRejections = new Counter('duplicate_rejections');
const otherBusinessRejections = new Counter('other_business_rejections');
const successfulOrders = new Counter('successful_orders');
const debugErrorsEnabled = __ENV.K6_DEBUG_ERRORS === '1';
let debugErrorsPrinted = 0;

function parseTokens(raw) {
  return raw
    .split('\n')
    .map((line) => line.trim())
    .filter((line) => line.length > 0 && !line.startsWith('userId'))
    .map((line) => {
      const parts = line.split(',').map((part) => part.trim());
      return { userId: parts[0], token: parts[1] };
    })
    .filter((entry) => entry.userId && entry.token);
}

const tokenPool = parseTokens(rawTokens);
const selectedTokens = limitTokenPool(tokenPool, tokenCount);

if (selectedTokens.length === 0) {
  fail('loadtest/k6/data/token-users.csv does not contain any usable tokens');
}

if (!fixtureVoucher || !fixtureVoucher.voucherId) {
  fail('loadtest/k6/data/fixture-voucher.json is missing voucherId');
}

export const options = {
  scenarios: {
    seckill: {
      exec: 'seckill',
      ...buildSeckillScenario(benchmarkQps, benchmarkDuration),
    },
  },
  thresholds: {
    http_req_failed: ['rate<0.01'],
    system_errors: ['rate<0.01'],
  },
};

export function seckill() {
  const tokenEntry = pickTokenForRequest(selectedTokens, __VU, __ITER);
  const headers = {
    authorization: tokenEntry.token,
  };

  const res = http.post(`${baseUrl}/voucher-order/seckill/${fixtureVoucher.voucherId}`, null, { headers });

  const isSystemError = res.status !== 200;
  systemErrors.add(isSystemError ? 1 : 0);

  if (debugErrorsEnabled && isSystemError && debugErrorsPrinted < 10) {
    debugErrorsPrinted += 1;
    console.log(`system error status=${res.status} body=${res.body}`);
  }

  let isSuccess = false;
  let errorMsg = '';

  if (!isSystemError) {
    try {
      const body = res.json();
      isSuccess = body && body.success === true;
      errorMsg = body && typeof body.errorMsg === 'string' ? body.errorMsg : '';
    } catch (_) {
      systemErrors.add(1);
      if (debugErrorsEnabled && debugErrorsPrinted < 10) {
        debugErrorsPrinted += 1;
        console.log(`json parse failed status=${res.status} body=${res.body}`);
      }
      return;
    }
  }

  if (!isSuccess && errorMsg) {
    if (errorMsg.includes('库存不足')) {
      stockRejections.add(1);
    } else if (errorMsg.includes('不能重复下单')) {
      duplicateRejections.add(1);
    } else {
      otherBusinessRejections.add(1);
    }
  }

  if (isSuccess) {
    successfulOrders.add(1);
  }

  check(res, {
    'status is 200': (response) => response.status === 200,
    'body is parseable or rejected by business': () => !isSystemError,
  });
}
