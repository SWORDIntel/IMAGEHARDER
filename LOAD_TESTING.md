# Load Testing Guide

This document describes how to perform load testing on the Media Hardening service using K6.

## Prerequisites

Install K6:

**macOS:**
```bash
brew install k6
```

**Linux (Debian/Ubuntu):**
```bash
sudo gpg -k
sudo gpg --no-default-keyring --keyring /usr/share/keyrings/k6-archive-keyring.gpg --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys C5AD17C747E3415A3642D57D77C6C491D6AC1D69
echo "deb [signed-by=/usr/share/keyrings/k6-archive-keyring.gpg] https://dl.k6.io/deb stable main" | sudo tee /etc/apt/sources.list.d/k6.list
sudo apt-get update
sudo apt-get install k6
```

**Linux (Fedora/CentOS/RHEL):**
```bash
sudo dnf install https://dl.k6.io/rpm/repo.rpm
sudo dnf install k6
```

**Using Docker:**
```bash
docker pull grafana/k6
```

## Running Load Tests

### Quick Start (Smoke Test)

Test with 5 concurrent users for 2 minutes:

```bash
k6 run load-test.js
```

### Custom Configuration

Set environment variables:

```bash
export BASE_URL="http://localhost:8080"
export MEDIA_PROCESSOR_URL="http://localhost:9000"
k6 run load-test.js
```

### Test Scenarios

Edit `load-test.js` and uncomment the desired scenario:

**Scenario 1: Smoke Test (Default)**
- 5 concurrent users
- Duration: 2 minutes
- Purpose: Quick validation

**Scenario 2: Load Test**
```javascript
stages: [
  { duration: '2m', target: 50 },
  { duration: '5m', target: 50 },
  { duration: '2m', target: 0 },
],
```
- 50 concurrent users
- Duration: 9 minutes
- Purpose: Sustained load testing

**Scenario 3: Stress Test**
```javascript
stages: [
  { duration: '2m', target: 100 },
  { duration: '5m', target: 100 },
  { duration: '2m', target: 200 },
  { duration: '5m', target: 200 },
  { duration: '2m', target: 0 },
],
```
- Up to 200 concurrent users
- Duration: 16 minutes
- Purpose: Find breaking point

**Scenario 4: Spike Test**
```javascript
stages: [
  { duration: '1m', target: 10 },
  { duration: '30s', target: 200 },
  { duration: '1m', target: 200 },
  { duration: '30s', target: 10 },
  { duration: '1m', target: 0 },
],
```
- Sudden spike to 200 users
- Duration: 4 minutes
- Purpose: Test sudden traffic burst

## Advanced Options

### Output to JSON

```bash
k6 run --out json=load-test-results.json load-test.js
```

### Output to InfluxDB

```bash
k6 run --out influxdb=http://localhost:8086/k6 load-test.js
```

### Custom Thresholds

```bash
k6 run --summary-export=summary.json load-test.js
```

### Run with Docker

```bash
docker run --rm -i --network="host" \
  -e BASE_URL="http://localhost:8080" \
  grafana/k6 run - < load-test.js
```

## Monitoring During Load Tests

### View Prometheus Metrics

```bash
watch -n 1 'curl -s http://localhost:8080/metrics | grep media_processor'
```

### View Grafana Dashboards

Open: http://localhost:3000

Dashboards:
- **Media Hardening - Processing Metrics**: Real-time processing stats
- **Media Hardening - Security Monitoring**: Security events during load

### View Live K6 Output

K6 provides real-time output during the test:

```
     ✓ health check status 200
     ✓ metrics endpoint accessible

     █ setup

     checks.........................: 100.00% ✓ 150       ✗ 0
     data_received..................: 1.5 MB  50 kB/s
     data_sent......................: 15 kB   500 B/s
     errors.........................: 0.00%   ✓ 0         ✗ 150
     files_processed................: 150     5/s
     http_req_blocked...............: avg=1.2ms    min=100µs   med=500µs   max=10ms    p(95)=3ms
     http_req_connecting............: avg=500µs    min=50µs    med=200µs   max=2ms     p(95)=1ms
     http_req_duration..............: avg=150ms    min=50ms    med=100ms   max=500ms   p(95)=300ms
     http_req_failed................: 0.00%   ✓ 0         ✗ 300
     http_req_receiving.............: avg=1ms      min=100µs   med=500µs   max=5ms     p(95)=2ms
     http_req_sending...............: avg=500µs    min=50µs    med=200µs   max=2ms     p(95)=1ms
     http_req_tls_handshaking.......: avg=0s       min=0s      med=0s      max=0s      p(95)=0s
     http_req_waiting...............: avg=148ms    min=49ms    med=99ms    max=498ms   p(95)=298ms
     http_reqs......................: 300     10/s
     iteration_duration.............: avg=2.5s     min=1s      med=2s      max=5s      p(95)=4s
     iterations.....................: 150     5/s
     processing_duration............: avg=800ms    min=500ms   med=750ms   max=5000ms  p(99)=3000ms
     security_violations............: 0       0/s
     vus............................: 5       min=0       max=5
     vus_max........................: 5       min=5       max=5
```

## Interpreting Results

### Key Metrics

| Metric | Good | Warning | Critical |
|--------|------|---------|----------|
| `http_req_duration` p(95) | < 2s | 2-5s | > 5s |
| `http_req_failed` rate | < 1% | 1-10% | > 10% |
| `processing_duration` p(99) | < 5s | 5-10s | > 10s |
| `errors` rate | 0% | < 5% | > 5% |
| `security_violations` | 0 | Low rate | High rate |

### Common Issues

**High Error Rate**
- Check container resource limits
- Increase CPU/memory in docker-compose.yml or kubernetes-deployment.yaml
- Review error logs: `docker logs media-processor-hardened`

**High Latency**
- Check disk I/O (especially for video processing)
- Verify no CPU throttling
- Check Prometheus metrics for resource saturation

**Security Violations**
- Review Grafana security dashboard
- Check quarantine directory: `ls -la ./quarantine/`
- Analyze suspicious files

## Best Practices

1. **Baseline First**: Run smoke test on production-like environment to establish baseline
2. **Incremental Load**: Gradually increase load in stress tests
3. **Monitor Resources**: Watch CPU, memory, disk I/O during tests
4. **Real Test Data**: Use representative media files (not just minimal test files)
5. **Repeated Tests**: Run multiple times to account for variance
6. **Document Results**: Save JSON output and screenshots of dashboards

## CI/CD Integration

Add to GitHub Actions (`.github/workflows/load-test.yml`):

```yaml
name: Load Test

on:
  schedule:
    - cron: '0 2 * * 0'  # Weekly on Sunday at 2 AM
  workflow_dispatch:      # Manual trigger

jobs:
  load-test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Start services
        run: docker-compose up -d

      - name: Wait for services
        run: sleep 30

      - name: Install K6
        run: |
          sudo gpg -k
          sudo gpg --no-default-keyring --keyring /usr/share/keyrings/k6-archive-keyring.gpg --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys C5AD17C747E3415A3642D57D77C6C491D6AC1D69
          echo "deb [signed-by=/usr/share/keyrings/k6-archive-keyring.gpg] https://dl.k6.io/deb stable main" | sudo tee /etc/apt/sources.list.d/k6.list
          sudo apt-get update
          sudo apt-get install k6

      - name: Run load test
        run: k6 run --summary-export=summary.json load-test.js

      - name: Upload results
        uses: actions/upload-artifact@v3
        with:
          name: load-test-results
          path: |
            load-test-results.json
            summary.json

      - name: Check thresholds
        run: |
          if grep -q '"failed": true' summary.json; then
            echo "Load test thresholds failed!"
            exit 1
          fi
```

## Troubleshooting

### K6 Can't Connect to Service

```bash
# Check if service is running
curl http://localhost:8080/health

# Check Docker containers
docker ps

# Check logs
docker logs media-processor-hardened
```

### Metrics Not Available

```bash
# Verify Prometheus is scraping
curl http://localhost:9090/api/v1/targets

# Check metrics endpoint directly
curl http://localhost:8080/metrics | grep media_processor
```

### Out of Memory During Load Test

Increase Docker resources:

```yaml
# docker-compose.yml
services:
  media-processor:
    deploy:
      resources:
        limits:
          memory: 4G  # Increase from 2G
```

## Further Reading

- [K6 Documentation](https://k6.io/docs/)
- [K6 Cloud for CI/CD](https://k6.io/cloud/)
- [Grafana K6 Dashboard](https://grafana.com/grafana/dashboards/2587)
- [Performance Testing Best Practices](https://k6.io/docs/testing-guides/automated-performance-testing/)
