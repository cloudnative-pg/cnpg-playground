#!/usr/bin/env bash
#
# This script tears down the Prometheus and Grafana operators from the
# CloudNativePG playground environment.
# When run without arguments, it automatically detects all cnpg-playground
# Kind clusters in your environment and removes the monitoring stack from each.
# To remove monitoring for specific regions only, pass the region names as arguments.
#
#
# Copyright The CloudNativePG Contributors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

# Source the common setup script
source $(git rev-parse --show-toplevel)/scripts/common.sh

# --- Main Logic ---
# Determine regions from arguments, or auto-detect if none are provided
detect_running_regions "$@"

if [ ${#REGIONS[@]} -eq 0 ]; then
    echo "🤷 No regions found to tear down monitoring from. Exiting."
    exit 0
fi

echo "🔥 Tearing down monitoring from regions: ${REGIONS[*]}"

for region in "${REGIONS[@]}"; do
    echo "-------------------------------------------------------------"
    echo " 🔥 Removing monitoring resources from region: ${region}"
    echo "-------------------------------------------------------------"

    K8S_CLUSTER_NAME=$(get_cluster_name "${region}")
    CONTEXT_NAME=$(get_cluster_context "${region}")

    # Check if cluster exists
    if ! kind get clusters | grep -q "^${K8S_CLUSTER_NAME}$"; then
        echo "⚠️  Cluster '${K8S_CLUSTER_NAME}' not found, skipping region '${region}'"
        continue
    fi

    echo "📈 Removing Grafana resources..."
    # Delete Grafana instance and dashboards
    kubectl kustomize ${GIT_REPO_ROOT}/monitoring/grafana/ 2>/dev/null | \
      kubectl --context ${CONTEXT_NAME} delete --ignore-not-found=true -f - 2>/dev/null || true

    # Delete Grafana operator
    echo "📈 Removing Grafana operator..."
    kubectl --context ${CONTEXT_NAME} delete --ignore-not-found=true \
      -f https://github.com/grafana/grafana-operator/releases/latest/download/kustomize-cluster_scoped.yaml || true

    echo "🔧 Removing kubelet monitoring resources..."
    kubectl --context ${CONTEXT_NAME} delete --ignore-not-found=true \
      -f ${GIT_REPO_ROOT}/monitoring/prometheus-instance/servicemonitor-kubelet.yaml 2>/dev/null || true
    
    echo "🔥 Removing Prometheus resources..."
    kubectl kustomize ${GIT_REPO_ROOT}/monitoring/prometheus-instance 2>/dev/null | \
      kubectl --context ${CONTEXT_NAME} delete --ignore-not-found=true -f - 2>/dev/null || true
    kubectl kustomize ${GIT_REPO_ROOT}/monitoring/prometheus-operator 2>/dev/null | \
      kubectl --context ${CONTEXT_NAME} delete --ignore-not-found=true -f - 2>/dev/null || true
    
    echo "🖥️  Removing node-exporter..."
    kubectl kustomize ${GIT_REPO_ROOT}/monitoring/node-exporter 2>/dev/null | \
      kubectl --context ${CONTEXT_NAME} delete --ignore-not-found=true -f - 2>/dev/null || true
    
    echo "📊 Removing kube-state-metrics..."
    kubectl kustomize ${GIT_REPO_ROOT}/monitoring/kube-state-metrics 2>/dev/null | \
      kubectl --context ${CONTEXT_NAME} delete --ignore-not-found=true -f - 2>/dev/null || true

    echo "🗑️  Removing prometheus-operator namespace..."
    kubectl --context ${CONTEXT_NAME} delete namespace prometheus-operator --ignore-not-found=true || true

    echo "✅ Monitoring teardown complete for region: ${region}"
    echo
done

echo "✅ Monitoring cleanup complete!"

