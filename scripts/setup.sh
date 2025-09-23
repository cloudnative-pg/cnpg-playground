#!/usr/bin/env bash
#
# This script sets up a simulated environment for deploying CloudNativePG
# across two regions: Europe and the USA. Each region includes its own
# Kubernetes cluster and a dedicated object storage system for backups,
# using an external MinIO instance in Docker to emulate an S3-compatible
# object store.
#
# The Kubernetes clusters in each region consist of multiple nodes, each with
# specialized roles—managing the control plane, handling infrastructure workloads,
# hosting applications, and running PostgreSQL databases.
#
# Note: This environment is for learning purposes only and should not be used
# in production.
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
source "$(dirname "$0")/common.sh"

echo "✅ Prerequisites met. Using '$CONTAINER_PROVIDER' as the container provider."

# --- Pre-flight Check ---
echo "🔎 Verifying that no existing playground clusters are running..."
# The '|| true' prevents the script from exiting if grep finds no matches.
existing_count=$(kind get clusters | grep -c "^${K8S_BASE_NAME}-" || true)

if [ "${existing_count}" -gt 0 ]; then
    echo "❌ Error: Found ${existing_count} existing playground cluster(s)."
    echo "Please run './scripts/teardown.sh' to remove the existing environment before running setup."
    echo
    echo "Found clusters:"
    kind get clusters | grep "^${K8S_BASE_NAME}-"
    exit 1
fi

echo "✅ No existing clusters found. Proceeding with setup."
echo

# --- Script Setup ---
# Determine regions from arguments, or use defaults
REGIONS=("$@")
if [ ${#REGIONS[@]} -eq 0 ]; then
    REGIONS=("eu" "us")
fi

# Setup a single, shared Kubeconfig for all clusters
export KUBECONFIG="${KUBE_CONFIG_PATH}"
> "${KUBE_CONFIG_PATH}" # Create or clear the kubeconfig file
cd "${GIT_REPO_ROOT}"
kind_config_path="${GIT_REPO_ROOT}/k8s/kind-cluster.yaml"

# --- Main Loop for Regions ---
let "current_minio_port = MINIO_BASE_PORT"
declare -A minio_ports

for region in "${REGIONS[@]}"; do
    echo "--------------------------------------------------"
    echo "🚀 Setting up region: ${region}"
    echo "--------------------------------------------------"

    K8S_CLUSTER_NAME="${K8S_BASE_NAME}-${region}"
    MINIO_CONTAINER_NAME="${MINIO_BASE_NAME}-${region}"

    echo "📦 Creating MinIO container '${MINIO_CONTAINER_NAME}' on host port ${current_minio_port}..."
    mkdir -p "${GIT_REPO_ROOT}/${MINIO_CONTAINER_NAME}"
    $CONTAINER_PROVIDER run \
        --name "${MINIO_CONTAINER_NAME}" -d -p "${current_minio_port}:9001" \
        -v "${GIT_REPO_ROOT}/${MINIO_CONTAINER_NAME}:/data" \
        -e "MINIO_ROOT_USER=${MINIO_ROOT_USER}" -e "MINIO_ROOT_PASSWORD=${MINIO_ROOT_PASSWORD}" \
        -u "$(id -u):$(id -g)" \
        "${MINIO_IMAGE}" server /data --console-address ":9001" > /dev/null

    echo "🏗️  Creating Kind cluster '${K8S_CLUSTER_NAME}'..."
    kind create cluster --config "${kind_config_path}" --name "${K8S_CLUSTER_NAME}"

    echo "🏷️  Labeling nodes in '${K8S_CLUSTER_NAME}'..."
    kubectl label node -l postgres.node.kubernetes.io node-role.kubernetes.io/postgres=
    kubectl label node -l infra.node.kubernetes.io node-role.kubernetes.io/infra=
    kubectl label node -l app.node.kubernetes.io node-role.kubernetes.io/app=

    echo "🌐 Connecting MinIO to the Kind network..."
    $CONTAINER_PROVIDER network connect kind "${MINIO_CONTAINER_NAME}"

    echo "🔑 Creating MinIO secret in cluster..."
    kubectl create secret generic "${MINIO_CONTAINER_NAME}" \
        --context "kind-${K8S_CLUSTER_NAME}" \
        --from-literal=ACCESS_KEY_ID="$MINIO_ROOT_USER" \
        --from-literal=ACCESS_SECRET_KEY="$MINIO_ROOT_PASSWORD"

    echo "✅ Region '${region}' setup complete."
    minio_ports["${region}"]="${current_minio_port}"
    ((current_minio_port++))
done

# Display information
source "$(dirname "$0")/info.sh"
