import http from 'k6/http';
import { check, fail } from 'k6';

const baseUrl = __ENV.BASE_URL || 'http://127.0.0.1:8081';
const rawShopIds = open('./data/shop-ids.csv');

function parseShopIds(raw) {
  return raw
    .split('\n')
    .map((line) => line.trim())
    .map((line) => line.split(',')[0].trim())
    .filter((id) => /^[0-9]+$/.test(id));
}

const shopIds = parseShopIds(rawShopIds);

if (shopIds.length === 0) {
  fail('loadtest/k6/data/shop-ids.csv does not contain any shop IDs');
}

export const options = {
  scenarios: {
    read: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '1m', target: 50 },
        { duration: '5m', target: 200 },
        { duration: '30s', target: 0 },
      ],
      gracefulRampDown: '30s',
    },
  },
  thresholds: {
    http_req_failed: ['rate<0.01'],
    http_req_duration: ['p(95)<200'],
  },
};

export default function () {
  const shopId = shopIds[Math.floor(Math.random() * shopIds.length)];
  const res = http.get(`${baseUrl}/shop/${shopId}`);

  check(res, {
    'status is 200': (response) => response.status === 200,
    'response is success payload': (response) => {
      try {
        const body = response.json();
        return body && body.success === true;
      } catch (_) {
        return false;
      }
    },
  });
}
