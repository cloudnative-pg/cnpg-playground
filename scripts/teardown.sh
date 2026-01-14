#!/usr/bin/env bash
#
# This script tears down the CloudNativePG playground environment.
# It auto-detects all regions if none are specified. If regions are
# provided as arguments, it only tears down those specific regions.
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

# --- Main Logic ---
# Determine regions from arguments, or auto-detect if none are provided
detect_running_regions "$@"

if [ ${#REGIONS[@]} -eq 0 ]; then
    echo "🤷 No regions found to tear down. Exiting."
    exit 0
fi

echo "🔥 Tearing down regions: ${REGIONS[*]}"

for region in "${REGIONS[@]}"; do
    K8S_CLUSTER_NAME=$(get_cluster_name "${region}")
    CONTEXT_NAME=$(get_cluster_context "${region}")
    MINIO_CONTAINER_NAME="${MINIO_BASE_NAME}-${region}"

    echo "--------------------------------------------------"
    echo "🔥 Tearing down region: ${region}"
    echo "--------------------------------------------------"

    # Delete Kind cluster
    if [[ $(kind get clusters) == *"${K8S_CLUSTER_NAME}"* ]]; then
        echo "🗑️  Deleting Kind cluster '${K8S_CLUSTER_NAME}'..."
        kind delete cluster --name "${K8S_CLUSTER_NAME}"
    else
        echo "🔷 Kind cluster '${K8S_CLUSTER_NAME}' not found, skipping."
    fi

    # Stop and remove MinIO container
    if [[ $($CONTAINER_PROVIDER ps -a --format '{{.Names}}') == *"${MINIO_CONTAINER_NAME}"* ]]; then
        echo "🗑️  Removing MinIO container '${MINIO_CONTAINER_NAME}'..."
        $CONTAINER_PROVIDER rm -f "${MINIO_CONTAINER_NAME}" > /dev/null
    else
        echo "🔷 MinIO container '${MINIO_CONTAINER_NAME}' not found, skipping."
    fi

    # Remove MinIO data directory
    if [ -d "${GIT_REPO_ROOT}/${MINIO_CONTAINER_NAME}" ]; then
        echo "🗑️  Removing MinIO data directory..."
        rm -rf "${GIT_REPO_ROOT}/${MINIO_CONTAINER_NAME}"
    fi

    # Clean up kubeconfig entry for the deleted cluster
    if [ -f "${KUBE_CONFIG_PATH}" ]; then
        echo "🧹 Cleaning up kubeconfig entries for context '${CONTEXT_NAME}'..."
        kubectl config delete-context "${CONTEXT_NAME}" --kubeconfig "${KUBE_CONFIG_PATH}" > /dev/null 2>&1 || true
        kubectl config delete-cluster "${K8S_CLUSTER_NAME}" --kubeconfig "${KUBE_CONFIG_PATH}" > /dev/null 2>&1 || true
    fi
done

echo ""
echo "✅ Cleanup complete!"
