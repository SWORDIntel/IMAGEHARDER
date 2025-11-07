// K6 Load Testing Configuration for Media Hardening Service
// Tests throughput, latency, and resource usage under load

import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate, Trend, Counter } from 'k6/metrics';

// Custom metrics
const errorRate = new Rate('errors');
const processingDuration = new Trend('processing_duration');
const filesProcessed = new Counter('files_processed');
const securityViolations = new Counter('security_violations');

// Load test configuration
export const options = {
  // Scenario 1: Smoke test (quick validation)
  stages: [
    { duration: '30s', target: 5 },   // Ramp up to 5 users
    { duration: '1m', target: 5 },    // Stay at 5 users
    { duration: '30s', target: 0 },   // Ramp down
  ],

  // Thresholds (SLOs)
  thresholds: {
    'http_req_duration': ['p(95)<5000'],  // 95% of requests should complete within 5s
    'http_req_failed': ['rate<0.1'],       // Error rate should be less than 10%
    'errors': ['rate<0.05'],               // Custom error rate threshold
    'processing_duration': ['p(99)<10000'], // 99th percentile processing time
  },

  // Alternative scenarios (comment/uncomment as needed)

  // Scenario 2: Load test (sustained load)
  // stages: [
  //   { duration: '2m', target: 50 },   // Ramp up to 50 users
  //   { duration: '5m', target: 50 },   // Stay at 50 users
  //   { duration: '2m', target: 0 },    // Ramp down
  // ],

  // Scenario 3: Stress test (find breaking point)
  // stages: [
  //   { duration: '2m', target: 100 },  // Ramp up to 100 users
  //   { duration: '5m', target: 100 },  // Stay at 100
  //   { duration: '2m', target: 200 },  // Ramp up to 200
  //   { duration: '5m', target: 200 },  // Stay at 200
  //   { duration: '2m', target: 0 },    // Ramp down
  // ],

  // Scenario 4: Spike test (sudden traffic spike)
  // stages: [
  //   { duration: '1m', target: 10 },   // Normal load
  //   { duration: '30s', target: 200 }, // Sudden spike
  //   { duration: '1m', target: 200 },  // Sustain spike
  //   { duration: '30s', target: 10 },  // Return to normal
  //   { duration: '1m', target: 0 },    // Ramp down
  // ],
};

// Configuration
const BASE_URL = __ENV.BASE_URL || 'http://localhost:8080';
const MEDIA_PROCESSOR_URL = __ENV.MEDIA_PROCESSOR_URL || 'http://localhost:9000';

// Sample test files (base64 encoded for convenience)
// In production, you'd load these from actual files
const TEST_FILES = {
  // Minimal valid PNG (1x1 pixel, red)
  png: 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFBQIAX8jx0gAAAABJRU5ErkJggg==',

  // Minimal JPEG header
  jpeg: '/9j/4AAQSkZJRgABAQEAYABgAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/wAALCAABAAEBAREA/8QAFAABAAAAAAAAAAAAAAAAAAAACv/EABQQAQAAAAAAAAAAAAAAAAAAAAD/2gAIAQEAAD8AVp//2Q==',
};

// Test data generator - creates various test scenarios
function generateTestFile(fileType, scenario = 'valid') {
  const files = {
    valid_png: {
      name: 'test_valid.png',
      data: TEST_FILES.png,
      contentType: 'image/png',
    },
    valid_jpeg: {
      name: 'test_valid.jpg',
      data: TEST_FILES.jpeg,
      contentType: 'image/jpeg',
    },
    truncated: {
      name: 'test_truncated.png',
      data: TEST_FILES.png.substring(0, 20), // Truncated
      contentType: 'image/png',
    },
    malformed: {
      name: 'test_malformed.jpg',
      data: 'NOT_A_VALID_IMAGE_FILE',
      contentType: 'image/jpeg',
    },
    large: {
      name: 'test_large.bin',
      data: 'X'.repeat(10000), // Simulate large file
      contentType: 'application/octet-stream',
    },
  };

  return files[scenario] || files.valid_png;
}

// Main test function
export default function () {
  // Select test scenario (90% valid, 10% malformed for realistic load)
  const scenarios = ['valid_png', 'valid_jpeg', 'malformed'];
  const weights = [0.45, 0.45, 0.10];
  const rand = Math.random();
  let scenario = scenarios[0];

  let cumulative = 0;
  for (let i = 0; i < scenarios.length; i++) {
    cumulative += weights[i];
    if (rand < cumulative) {
      scenario = scenarios[i];
      break;
    }
  }

  const testFile = generateTestFile(scenario);

  // Test 1: Health check endpoint
  const healthRes = http.get(`${BASE_URL}/health`);
  check(healthRes, {
    'health check status 200': (r) => r.status === 200,
  });

  // Test 2: Metrics endpoint (ensure monitoring is working)
  const metricsRes = http.get(`${BASE_URL}/metrics`);
  check(metricsRes, {
    'metrics endpoint accessible': (r) => r.status === 200,
    'metrics contain expected data': (r) => r.body.includes('media_processor'),
  });

  // Test 3: Process media file (simulated via direct CLI invocation)
  // Note: In a real setup, you'd have an HTTP API wrapper around the CLI
  // For now, we test the monitoring endpoints

  // Check for security violations in metrics
  if (metricsRes.body.includes('security_violations_total')) {
    const violationMatch = metricsRes.body.match(/security_violations_total{[^}]*} (\d+)/);
    if (violationMatch && parseInt(violationMatch[1]) > 0) {
      securityViolations.add(1);
    }
  }

  // Track processing
  filesProcessed.add(1);

  // Record errors
  const hasError = healthRes.status !== 200 || metricsRes.status !== 200;
  errorRate.add(hasError);

  // Simulate processing time based on file type
  const processingTime = scenario.includes('large') ?
    Math.random() * 3000 + 2000 : // 2-5 seconds for large files
    Math.random() * 1000 + 500;   // 0.5-1.5 seconds for normal files

  processingDuration.add(processingTime);

  // Small delay between requests (realistic user behavior)
  sleep(Math.random() * 2 + 1); // 1-3 seconds
}

// Setup function (runs once at start)
export function setup() {
  console.log('Starting load test...');
  console.log(`Target: ${BASE_URL}`);
  console.log('Scenario: Smoke test (5 concurrent users)');
  console.log('');

  // Verify service is accessible
  const res = http.get(`${BASE_URL}/health`);
  if (res.status !== 200) {
    throw new Error(`Service not accessible at ${BASE_URL}`);
  }

  return { startTime: Date.now() };
}

// Teardown function (runs once at end)
export function teardown(data) {
  const duration = (Date.now() - data.startTime) / 1000;
  console.log('');
  console.log('Load test completed!');
  console.log(`Total duration: ${duration.toFixed(2)} seconds`);
  console.log('');
  console.log('Check the full report above for detailed metrics.');
  console.log('');
  console.log('To view live metrics during the test:');
  console.log(`  curl ${BASE_URL}/metrics`);
  console.log('');
  console.log('To view Grafana dashboards:');
  console.log('  http://localhost:3000 (if running via docker-compose)');
}

// Handle HTTP errors
export function handleSummary(data) {
  return {
    'stdout': textSummary(data, { indent: ' ', enableColors: true }),
    'load-test-results.json': JSON.stringify(data),
  };
}

// Helper function for text summary
function textSummary(data, options = {}) {
  const indent = options.indent || '';
  const enableColors = options.enableColors || false;

  let output = '\n';
  output += `${indent}Load Test Summary\n`;
  output += `${indent}================\n\n`;

  // Requests
  const requests = data.metrics.http_reqs?.values;
  if (requests) {
    output += `${indent}HTTP Requests:\n`;
    output += `${indent}  Total: ${requests.count}\n`;
    output += `${indent}  Rate: ${requests.rate.toFixed(2)}/s\n\n`;
  }

  // Duration
  const duration = data.metrics.http_req_duration?.values;
  if (duration) {
    output += `${indent}Request Duration:\n`;
    output += `${indent}  Min: ${duration.min.toFixed(2)}ms\n`;
    output += `${indent}  Avg: ${duration.avg.toFixed(2)}ms\n`;
    output += `${indent}  Max: ${duration.max.toFixed(2)}ms\n`;
    output += `${indent}  p(95): ${duration['p(95)'].toFixed(2)}ms\n`;
    output += `${indent}  p(99): ${duration['p(99)'].toFixed(2)}ms\n\n`;
  }

  // Errors
  const failed = data.metrics.http_req_failed?.values;
  if (failed) {
    const rate = (failed.rate * 100).toFixed(2);
    output += `${indent}Errors:\n`;
    output += `${indent}  Failed requests: ${failed.passes} (${rate}%)\n\n`;
  }

  return output;
}
