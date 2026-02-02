#!/usr/bin/env bash
# End-to-end smoke test for cnpg-playground - Part 2: Teardown & Recreation
# Usage: ./test-2-teardown.sh  OR  nix develop -c ./test-2-teardown.sh
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

# Pre-flight check: Verify database is running before teardown tests
log "Pre-flight check: Verifying database is running..."
for region in eu us; do 
  CTX=$(get_cluster_context "${region}")
  kubectl --context "${CTX}" wait --for=condition=Ready pod -l cnpg.io/cluster=pg-${region} --timeout=10s && \
    pass "${region}: PostgreSQL running" || { fail "${region}: PostgreSQL not ready. Run test-1-setup.sh first."; exit 1; }
done

# Test teardown and recreation of PostgreSQL layer
log "Tearing down PostgreSQL clusters..."
"${ROOT}/demo/teardown.sh" && pass "PostgreSQL teardown" || fail "PostgreSQL teardown"
sleep 10   # extra time for pods to shut down (otherwise, the following test occasionally fails)

for region in eu us; do
  CTX=$(get_cluster_context "${region}")
  PGPODS=$(kubectl --context "${CTX}" get pods -l cnpg.io/cluster=pg-${region} --no-headers | wc -l || echo "0")
  [ "${PGPODS}" -eq 0 ] && pass "${region}: PostgreSQL removed" || fail "${region}: PostgreSQL still exists"
done

log "Recreating PostgreSQL clusters..."
if LEGACY=true "${ROOT}/demo/setup.sh"; then pass "PostgreSQL re-setup"; else fail "PostgreSQL re-setup"; exit 1; fi

for region in eu us; do
  CTX=$(get_cluster_context "${region}")
  kubectl --context "${CTX}" wait --for=condition=Ready pod -l cnpg.io/cluster=pg-${region} --timeout=30s && \
    pass "${region}: PostgreSQL ready" || fail "${region}: PostgreSQL not ready"
done

# Test teardown and recreation of monitoring layer
log "Tearing down monitoring stack..."
"${ROOT}/monitoring/teardown.sh" && pass "Monitoring teardown" || fail "Monitoring teardown"

for region in eu us; do
  CTX=$(get_cluster_context "${region}")
  for ns in prometheus-operator grafana; do
    ! kubectl --context "${CTX}" get namespace "${ns}" && \
      pass "${region}: ${ns} removed" || fail "${region}: ${ns} still exists"
  done
done

log "Recreating monitoring stack..."
if "${ROOT}/monitoring/setup.sh"; then pass "Monitoring re-setup"; else fail "Monitoring re-setup"; exit 1; fi

for region in eu us; do
  CTX=$(get_cluster_context "${region}")
  kubectl --context "${CTX}" wait --for=condition=Ready pod -l app.kubernetes.io/name=prometheus \
    -n prometheus-operator --timeout=90s && \
    pass "${region}: Prometheus ready" || fail "${region}: Prometheus not ready"
  
  kubectl --context "${CTX}" wait --for=condition=Ready pod -l app=grafana \
    -n grafana --timeout=90s && \
    pass "${region}: Grafana ready" || fail "${region}: Grafana not ready"
done

# Test infrastructure teardown
log "Tearing down infrastructure..."
"${ROOT}/scripts/teardown.sh" && pass "Infrastructure teardown" || fail "Infrastructure teardown"
for region in eu us; do
  CLUSTER_NAME=$(get_cluster_name "${region}")
  ! kind get clusters | grep -qx "${CLUSTER_NAME}" && \
    pass "${region}: Cluster removed" || fail "${region}: Cluster still exists"
  
  # Verify MinIO containers are removed
  MINIO_NAME="${MINIO_BASE_NAME}-${region}"
  ! docker ps -a --format '{{.Names}}' | grep -qx "${MINIO_NAME}" && \
    pass "${region}: MinIO container removed" || fail "${region}: MinIO container still exists"
done

cleanup

# Summary
log "=========================================="
log "Results: ${PASSED} passed, ${FAILED} failed"
[ ${FAILED} -eq 0 ] && { log "✅ All tests PASSED"; exit 0; } || { log "❌ FAILED"; exit 1; }

