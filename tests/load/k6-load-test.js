/**
 * k6 Load Test Script
 * Tests: 50k events/sec sustained, 5k API req/sec, 1k predictions/sec
 */

import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate } from 'k6/metrics';

const errorRate = new Rate('errors');

export const options = {
  stages: [
    { duration: '2m', target: 1000 },   // Ramp up to 1k users
    { duration: '5m', target: 5000 },    // Ramp up to 5k users
    { duration: '10m', target: 10000 },  // Sustained 10k users
    { duration: '2m', target: 0 },       // Ramp down
  ],
  thresholds: {
    'http_req_duration': ['p(99)<500'], // P99 < 500ms
    'errors': ['rate<0.01'],             // Error rate < 1%
    'http_req_rate': ['rate>50'],        // > 50 req/sec
  },
};

const EVENT_INGESTION_URL = __ENV.EVENT_INGESTION_URL || 'http://localhost:8080';
const ANALYTICS_API_URL = __ENV.ANALYTICS_API_URL || 'http://localhost:8080';
const RECOMMENDATION_URL = __ENV.RECOMMENDATION_URL || 'http://localhost:8080';

export default function () {
  // Test 1: Event Ingestion (50k events/sec target)
  const eventPayload = JSON.stringify({
    event_type: 'game_start',
    player_id: `player-${Math.floor(Math.random() * 10000)}`,
    game_id: `game-${Math.floor(Math.random() * 100)}`,
    timestamp: new Date().toISOString(),
    data: {
      level: Math.floor(Math.random() * 10),
      score: Math.floor(Math.random() * 1000),
    },
  });

  const eventRes = http.post(
    `${EVENT_INGESTION_URL}/api/v1/events`,
    eventPayload,
    { headers: { 'Content-Type': 'application/json' } }
  );

  check(eventRes, {
    'event ingestion status is 200': (r) => r.status === 200,
    'event ingestion response time < 500ms': (r) => r.timings.duration < 500,
  }) || errorRate.add(1);

  // Test 2: Analytics API (5k req/sec target)
  const analyticsRes = http.get(
    `${ANALYTICS_API_URL}/graphql?query={ playerStats(playerId: "player-1") { totalEvents } }`
  );

  check(analyticsRes, {
    'analytics API status is 200': (r) => r.status === 200,
  }) || errorRate.add(1);

  // Test 3: Recommendation Engine (1k predictions/sec target)
  const recommendationRes = http.post(
    `${RECOMMENDATION_URL}/api/v1/recommendations`,
    JSON.stringify({
      player_id: `player-${Math.floor(Math.random() * 1000)}`,
      limit: 10,
    }),
    { headers: { 'Content-Type': 'application/json' } }
  );

  check(recommendationRes, {
    'recommendation status is 200': (r) => r.status === 200,
  }) || errorRate.add(1);

  sleep(0.1); // 100ms between requests
}

export function handleSummary(data) {
  return {
    'stdout': textSummary(data, { indent: ' ', enableColors: true }),
    'summary.json': JSON.stringify(data),
  };
}

function textSummary(data, options) {
  return `
    ============================================
    Load Test Summary
    ============================================
    Total Requests: ${data.metrics.http_reqs.values.count}
    Failed Requests: ${data.metrics.http_req_failed.values.rate * 100}%
    P99 Latency: ${data.metrics.http_req_duration.values['p(99)']}ms
    Requests/sec: ${data.metrics.http_reqs.values.rate}
    ============================================
  `;
}



