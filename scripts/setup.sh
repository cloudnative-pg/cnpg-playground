#!/usr/bin/env bash
##
## Copyright © contributors to CloudNativePG, established as
## CloudNativePG a Series of LF Projects, LLC.
##
## Licensed under the Apache License, Version 2.0 (the "License");
## you may not use this file except in compliance with the License.
## You may obtain a copy of the License at
##
##     http://www.apache.org/licenses/LICENSE-2.0
##
## Unless required by applicable law or agreed to in writing, software
## distributed under the License is distributed on an "AS IS" BASIS,
## WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
## See the License for the specific language governing permissions and
## limitations under the License.
##
## SPDX-License-Identifier: Apache-2.0
##

#
# This script sets up a simulated environment for deploying CloudNativePG
# across two regions: Europe and the USA. Each region includes its own
# Kubernetes cluster and a dedicated object storage system for backups,
# using an external RustFS instance in Docker to emulate an S3-compatible
# object store.
#
# The Kubernetes clusters in each region consist of multiple nodes, each with
# specialized roles—managing the control plane, handling infrastructure workloads,
# hosting applications, and running PostgreSQL databases.
#
# Note: This environment is for learning purposes only and should not be used
# in production.
#

# Source the common setup script
source "$(dirname "$0")/common.sh"

echo "✅ Prerequisites met. Using '$CONTAINER_PROVIDER' as the container provider."

format_duration() {
    local s=$1
    printf "%dm %02ds" $((s / 60)) $((s % 60))
}

total_start=$SECONDS

# --- Pre-flight Check ---
echo "🔎 Verifying that no existing playground clusters are running..."
# The '|| true' prevents the script from exiting if grep finds no matches.
existing_count=$(kind get clusters | grep -c "^${K8S_BASE_NAME}" || true)

if [ "${existing_count}" -gt 0 ]; then
    echo "❌ Error: Found ${existing_count} existing playground cluster(s)."
    echo "Please run './scripts/teardown.sh' to remove the existing environment before running setup."
    echo
    echo "Found clusters:"
    kind get clusters | grep "^${K8S_BASE_NAME}"
    exit 1
fi

echo "✅ No existing clusters found. Proceeding with setup."
echo

# --- Script Setup ---
# Determine regions from arguments, or use defaults
set_regions "$@"

# Setup a single, shared Kubeconfig for all clusters
export KUBECONFIG="${KUBE_CONFIG_PATH}"
> "${KUBE_CONFIG_PATH}" # Create or clear the kubeconfig file
cd "${REPO_ROOT}"
kind_config_path="${REPO_ROOT}/k8s/kind-cluster.yaml"

# --- Phase 1: Provision Clusters and RustFS Instances ---
let "current_objectstore_port = RUSTFS_BASE_PORT"
declare -A objectstore_ports
declare -a all_objectstore_names=()

for region in "${REGIONS[@]}"; do
    echo "--------------------------------------------------"
    echo "🚀 Provisioning resources for region: ${region}"
    echo "--------------------------------------------------"
    region_start=$SECONDS

    K8S_CLUSTER_NAME=$(get_cluster_name "${region}")
    RUSTFS_CONTAINER_NAME="${RUSTFS_BASE_NAME}-${region}"

    echo "📦 Creating RustFS container '${RUSTFS_CONTAINER_NAME}' on host port ${current_objectstore_port}..."
    $CONTAINER_PROVIDER volume create "${RUSTFS_CONTAINER_NAME}" > /dev/null
    $CONTAINER_PROVIDER run \
        --name "${RUSTFS_CONTAINER_NAME}" -d -p "${current_objectstore_port}:9001" \
        -v "${RUSTFS_CONTAINER_NAME}:/data" \
        -e "RUSTFS_ACCESS_KEY=${RUSTFS_ROOT_USER}" \
        -e "RUSTFS_SECRET_KEY=${RUSTFS_ROOT_PASSWORD}" \
        -e RUSTFS_CONSOLE_ENABLE=true \
        --restart unless-stopped \
        "${RUSTFS_IMAGE}" --console-enable /data

    echo "🏗️  Creating Kind cluster '${K8S_CLUSTER_NAME}'..."
    if [ "$CONTAINER_PROVIDER" == "podman" ]; then
        export KIND_EXPERIMENTAL_PROVIDER=podman
    fi
    kind create cluster --config "${kind_config_path}" --name "${K8S_CLUSTER_NAME}"

    echo "🏷️  Labeling nodes in '${K8S_CLUSTER_NAME}'..."
    kubectl label node -l postgres.node.kubernetes.io node-role.kubernetes.io/postgres=
    kubectl label node -l infra.node.kubernetes.io node-role.kubernetes.io/infra=
    kubectl label node -l app.node.kubernetes.io node-role.kubernetes.io/app=

    echo "🌐 Connecting RustFS to the Kind network..."
    $CONTAINER_PROVIDER network connect kind "${RUSTFS_CONTAINER_NAME}"

    echo "⏳ Waiting for '${RUSTFS_CONTAINER_NAME}' to be reachable on port 9000 from within the Kind network..."
    elapsed=0
    until $CONTAINER_PROVIDER exec "${K8S_CLUSTER_NAME}-control-plane" \
        bash -c "echo >/dev/tcp/${RUSTFS_CONTAINER_NAME}/9000" 2>/dev/null; do
        if [ "${elapsed}" -ge 60 ]; then
            echo "❌ Timed out: '${RUSTFS_CONTAINER_NAME}' is not reachable from '${K8S_CLUSTER_NAME}' after 60s."
            exit 1
        fi
        sleep 2
        ((elapsed += 2))
    done

    echo "✅ Resource provisioning for '${region}' complete in $(format_duration $((SECONDS - region_start)))."

    # Store details for the next phase
    objectstore_ports["${region}"]="${current_objectstore_port}"
    all_objectstore_names+=("${RUSTFS_CONTAINER_NAME}")
    ((current_objectstore_port++))
done

# --- Phase 2: Distribute RustFS Secrets to all Clusters ---
echo
echo "--------------------------------------------------"
echo "🔑 Distributing RustFS secrets to all clusters"
echo "--------------------------------------------------"
for target_region in "${REGIONS[@]}"; do
    target_cluster_context=$(get_cluster_context "${target_region}")
    echo "   -> Configuring secrets in cluster: ${target_cluster_context}"

    for source_objectstore_name in "${all_objectstore_names[@]}"; do
        echo "      - Creating secret for ${source_objectstore_name}"
        kubectl create secret generic "${source_objectstore_name}" \
            --context "${target_cluster_context}" \
            --from-literal=ACCESS_KEY_ID="$RUSTFS_ROOT_USER" \
            --from-literal=ACCESS_SECRET_KEY="$RUSTFS_ROOT_PASSWORD"
    done
done

# --- Phase 3: Verify Cross-Region Object Store Connectivity ---
echo
echo "--------------------------------------------------"
echo "🌐 Verifying cross-region object store connectivity"
echo "--------------------------------------------------"
for region in "${REGIONS[@]}"; do
    K8S_CLUSTER_NAME=$(get_cluster_name "${region}")
    for objectstore_name in "${all_objectstore_names[@]}"; do
        echo -n "   ⏳ ${K8S_CLUSTER_NAME} -> ${objectstore_name}:9000 ... "
        elapsed=0
        until $CONTAINER_PROVIDER exec "${K8S_CLUSTER_NAME}-control-plane" \
            bash -c "echo >/dev/tcp/${objectstore_name}/9000" 2>/dev/null; do
            if [ "${elapsed}" -ge 60 ]; then
                echo "❌ FAIL"
                echo "❌ Timed out: '${objectstore_name}' is not reachable from '${K8S_CLUSTER_NAME}' after 60s."
                exit 1
            fi
            sleep 2
            ((elapsed += 2))
        done
        echo "✅ OK"
    done
done

# --- Final Instructions ---
echo
echo "⏱️  Total setup time: $(format_duration $((SECONDS - total_start)))."
echo
# Display information using the info script
source "$(dirname "$0")/info.sh"
