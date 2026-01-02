#!/usr/bin/env bash
#
# This script automatically detects running CloudNativePG playground clusters
# and displays their status, including version, nodes, and pods.
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
source "$(dirname "$0")/common.sh"

# --- Script Setup ---
if [ ! -f "${KUBE_CONFIG_PATH}" ]; then
    echo "❌ Error: Kubeconfig file not found at '${KUBE_CONFIG_PATH}'"
    echo "Please run the setup.sh script first."
    exit 1
fi
export KUBECONFIG="${KUBE_CONFIG_PATH}"

# --- Auto-detect Regions ---
detect_running_regions

# --- Access Instructions ---
echo
echo "--------------------------------------------------"
echo "🕹️  Cluster Access Instructions"
echo "--------------------------------------------------"
echo
echo "To access your playground clusters, first set the KUBECONFIG environment variable:"
echo "export KUBECONFIG=${KUBE_CONFIG_PATH}"
echo
echo "Available cluster contexts:"
for region in "${REGIONS[@]}"; do
    echo "  • kind-${K8S_BASE_NAME}-${region}"
done
echo
echo "To switch to a specific cluster (e.g., the '${REGIONS[0]}' region), use:"
echo "kubectl config use-context kind-${K8S_BASE_NAME}-${REGIONS[0]}"
echo

# --- Main Info Loop ---
echo "--------------------------------------------------"
echo "ℹ️  Cluster Information"
echo "--------------------------------------------------"
for region in "${REGIONS[@]}"; do
    CONTEXT="kind-${K8S_BASE_NAME}-${region}"
    echo
    echo "🔷 Cluster: ${CONTEXT}"
    echo "==================================="
    echo "🔹 Version:"
    kubectl --context "${CONTEXT}" version
    echo
    echo "🔹 Nodes:"
    kubectl --context "${CONTEXT}" get nodes -o wide
    echo
    echo "🔹 Secrets:"
    kubectl --context "${CONTEXT}" get secrets
done
