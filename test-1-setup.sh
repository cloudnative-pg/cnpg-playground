#!/usr/bin/env bash
# End-to-end smoke test for cnpg-playground - Part 1: Setup & Validation
# Usage: ./test-1-setup.sh  OR  nix develop -c ./test-1-setup.sh
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
source "${ROOT}/scripts/common.sh"
export KUBECONFIG="${KUBE_CONFIG_PATH}"
PASSED=0 FAILED=0

pass() { echo "✅ $*"; PASSED=$((PASSED+1)); }
fail() { echo "❌ $*"; FAILED=$((FAILED+1)); return 1; }
log() { echo "🧪 $*"; }

for cmd in kind kubectl curl jq docker; do command -v "$cmd" >/dev/null || { fail "Missing: $cmd"; exit 1; }; done

cleanup() { pkill -f "kubectl port-forward" || true; }
trap cleanup EXIT

# Setup: infrastructure → monitoring → PostgreSQL  
log "Setting up infrastructure (eu, us)...  start at $(date +%H:%M:%S)"
if "${ROOT}/scripts/setup.sh"; then pass "Infrastructure setup finish at $(date +%H:%M:%S)"; else fail "Infrastructure setup"; exit 1; fi

# Test infrastructure health (MinIO API + Kubernetes API)
log "Testing infrastructure health..."
for region in eu us; do
  CTX=$(get_cluster_context "${region}")
  
  # Test Kubernetes API
  kubectl --context "${CTX}" get nodes && \
    pass "${region}: Kubernetes API responsive" || fail "${region}: Kubernetes API failed"
  
  # Test MinIO API
  MINIO_PORT=$((MINIO_BASE_PORT + $([ "$region" = "us" ] && echo 1 || echo 0)))
  MINIO_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:${MINIO_PORT}/minio/health/live || echo "000")
  [ "${MINIO_STATUS}" = "200" ] && \
    pass "${region}: MinIO API responsive" || fail "${region}: MinIO API failed (HTTP ${MINIO_STATUS})"
done

log "Setting up monitoring stack...  start at $(date +%H:%M:%S)"
if "${ROOT}/monitoring/setup.sh"; then pass "Monitoring setup finish at $(date +%H:%M:%S)"; else fail "Monitoring setup"; exit 1; fi

# Allow time for pod creation and initial metrics scraping
log "Waiting 60 seconds for pod creation and initial metrics scrape...  start wait at $(date +%H:%M:%S)"
sleep 60

# Test monitoring health (Prometheus + Grafana + node/system metrics)
log "Testing monitoring stack health..."
for region in eu us; do
  CTX=$(get_cluster_context "${region}")
  
  # Wait for Prometheus pod
  kubectl --context "${CTX}" wait --for=condition=Ready pod -l app.kubernetes.io/name=prometheus \
    -n prometheus-operator --timeout=90s && \
    pass "${region}: Prometheus pod ready" || fail "${region}: Prometheus pod not ready"
  
  # Wait for Grafana pod
  kubectl --context "${CTX}" wait --for=condition=Ready pod -l app=grafana \
    -n grafana --timeout=90s && \
    pass "${region}: Grafana pod ready" || fail "${region}: Grafana pod not ready"
done

for region in eu us; do
  # Test Prometheus HTTP and metrics
  CTX=$(get_cluster_context "${region}")
  PORT=9090; [ "$region" = "us" ] && PORT=9091
  kubectl port-forward -n prometheus-operator prometheus-prometheus-0 ${PORT}:9090 --context "${CTX}" &
  sleep 3

  [ "$(curl -s http://localhost:${PORT}/-/ready)" = "Prometheus Server is Ready." ] && \
    pass "${region}: Prometheus HTTP API" || fail "${region}: Prometheus HTTP failed"
  
  # Test node/system metrics (from kubelet/node-exporter)
  NODE_METRICS=$(curl -s "http://localhost:${PORT}/api/v1/query?query=up%7Bjob%3D%22kubelet%22%7D" | jq -r '.data.result | length' || echo "0")
  [ "${NODE_METRICS}" -ge 1 ] && \
    pass "${region}: Kubelet metrics available (${NODE_METRICS})" || fail "${region}: Kubelet metrics missing"
  
  CONTAINER_METRICS=$(curl -s "http://localhost:${PORT}/api/v1/query?query=container_cpu_usage_seconds_total" | jq -r '.data.result | length' || echo "0")
  [ "${CONTAINER_METRICS}" -ge 1 ] && \
    pass "${region}: Container metrics available (${CONTAINER_METRICS})" || fail "${region}: Container metrics missing"
  
  # Test Grafana HTTP
  GPORT=3000; [ "$region" = "us" ] && GPORT=3001
  kubectl port-forward -n grafana service/grafana-service ${GPORT}:3000 --context "${CTX}" &
  sleep 3
  
  GSTATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:${GPORT}/login || echo "000")
  [ "${GSTATUS}" = "200" ] && \
    pass "${region}: Grafana HTTP" || fail "${region}: Grafana HTTP failed"
done

cleanup

log "Deploying PostgreSQL clusters...  start at $(date +%H:%M:%S)"
if LEGACY=true "${ROOT}/demo/setup.sh"; then pass "PostgreSQL setup finish at $(date +%H:%M:%S)"; else fail "PostgreSQL setup"; exit 1; fi

# Test PostgreSQL health and metrics
log "Testing PostgreSQL clusters..."
for region in eu us; do
  CTX=$(get_cluster_context "${region}")
  log "Testing region: ${region}"
  
  # PostgreSQL readiness
  kubectl --context "${CTX}" wait --for=condition=Ready pod -l cnpg.io/cluster=pg-${region} --timeout=30s && \
    pass "${region}: PostgreSQL ready" || fail "${region}: PostgreSQL not ready"
  
  # SQL query test
  SQL=$(kubectl --context "${CTX}" exec pg-${region}-1 -- psql -U postgres -tAc "SELECT 1" | tr -d '\r' || echo "")
  [ "${SQL}" = "1" ] && pass "${region}: SQL query OK" || fail "${region}: SQL query failed"
done

# Test PostgreSQL metrics in Prometheus (needs time to scrape)
log "Waiting 60 seconds for PostgreSQL metrics to be scraped...  start wait at $(date +%H:%M:%S)"
sleep 60  # Increased from 45s to ensure both regions have time to scrape

cleanup  # Clean any lingering port-forwards

for region in eu us; do
  CTX=$(get_cluster_context "${region}")
  PORT=9090; [ "$region" = "us" ] && PORT=9091
  kubectl port-forward -n prometheus-operator prometheus-prometheus-0 ${PORT}:9090 --context "${CTX}" &
  sleep 3
  
  PGMETRICS=$(curl -s "http://localhost:${PORT}/api/v1/query?query=cnpg_collector_up" | jq -r '.data.result | length' || echo "0")
  [ "${PGMETRICS}" -ge 1 ] && \
    pass "${region}: PostgreSQL metrics (${PGMETRICS})" || fail "${region}: PostgreSQL metrics missing"
done

cleanup

# Test recording rules (needs evaluation time and historical data)
# Recording rules need ~5 minutes of metrics data for irate() to work
log "Waiting 3.5 minutes for recording rules to evaluate (data + buffer)...  start wait at $(date +%H:%M:%S)"
sleep 210  # 3.5 minutes wait for sufficient time series data

for region in eu us; do
  CTX=$(get_cluster_context "${region}")
  PORT=9090; [ "$region" = "us" ] && PORT=9091
  
  kubectl port-forward -n prometheus-operator prometheus-prometheus-0 ${PORT}:9090 --context "${CTX}" &
  sleep 3
  
  # Check if recording rule metrics exist
  RULE_METRICS=$(curl -s "http://localhost:${PORT}/api/v1/query" --data-urlencode "query=node_namespace_pod_container:container_cpu_usage_seconds_total:sum_irate{pod=~\"pg-${region}-.*\",namespace=\"default\",node!=\"\"}" | jq -r '.data.result | length' || echo "0")
  [ "${RULE_METRICS}" -ge 1 ] && \
    pass "${region}: Recording rule metrics (${RULE_METRICS})" || fail "${region}: Recording rule metrics missing"
done

cleanup

# Summary
log "=========================================="
log "Results: ${PASSED} passed, ${FAILED} failed"
[ ${FAILED} -eq 0 ] && { log "✅ All tests PASSED"; exit 0; } || { log "❌ FAILED"; exit 1; }

