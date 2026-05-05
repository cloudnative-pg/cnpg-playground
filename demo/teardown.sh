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
# This script tears down the demo example for CloudNativePG.
#
# Note: This environment is for learning purposes only and should not be used
# in production.
#

set -u
[[ "${DEBUG:-false}" == "true" ]] && set -x

# Source the common setup script
source "$(cd "$(dirname "$0")/.." && pwd)/scripts/common.sh"

kube_config_path="${KUBE_CONFIG_PATH}"

# Setup a separate Kubeconfig
cd "${REPO_ROOT}"
export KUBECONFIG="${kube_config_path}"

# Detect or use the provided regions
detect_running_regions "$@"

for region in "${REGIONS[@]}"; do

    CONTEXT_NAME=$(get_cluster_context "${region}")

    # Delete the Postgres cluster and its scheduled backup
    kubectl delete --context "${CONTEXT_NAME}" --ignore-not-found=true \
        cluster/pg-${region} \
        scheduledbackup/pg-${region}-backup

    # Delete the PodMonitor if Prometheus CRDs are present
    if kubectl --context "${CONTEXT_NAME}" get crd podmonitors.monitoring.coreos.com &>/dev/null; then
        kubectl delete --context "${CONTEXT_NAME}" --ignore-not-found=true \
            podmonitor/pg-${region}-podmonitor
    fi

    # Delete the Barman ObjectStore CR
    kubectl delete --context "${CONTEXT_NAME}" --ignore-not-found=true \
        objectstore/objectstore-${region}

    # Delete Barman Cloud Plugin
    kubectl delete --context "${CONTEXT_NAME}" --ignore-not-found=true -f \
        "https://github.com/cloudnative-pg/plugin-barman-cloud/releases/download/${BARMAN_CLOUD_PLUGIN_VERSION}/manifest.yaml"

    # Delete cert-manager
    kubectl delete --context "${CONTEXT_NAME}" --ignore-not-found=true -f \
        "https://github.com/cert-manager/cert-manager/releases/download/${CERT_MANAGER_VERSION}/cert-manager.yaml"

    # Delete CNPG operator
    cnpg_ver="${CNPG_VERSION#v}"
    cnpg_minor=$(printf '%s' "${cnpg_ver}" | cut -d. -f1,2)
    kubectl delete --context "${CONTEXT_NAME}" --ignore-not-found=true -f \
        "https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-${cnpg_minor}/releases/cnpg-${cnpg_ver}.yaml"

    # Remove backup data from the object store container
    ${CONTAINER_PROVIDER} exec objectstore-${region} rm -rf /data/backups/pg-${region}

done
