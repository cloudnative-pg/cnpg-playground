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
# shellcheck source=scripts/common.sh
source "$(cd "$(dirname "$0")/.." && pwd)/scripts/common.sh"

kube_config_path="${KUBE_CONFIG_PATH}"

# Setup a separate Kubeconfig
cd "${REPO_ROOT}"
export KUBECONFIG="${kube_config_path}"

# Detect or use the provided regions
detect_running_regions "$@"

for region in "${REGIONS[@]}"; do

    CONTEXT_NAME=$(get_cluster_context "${region}")

    # Delete the Postgres cluster and its scheduled backup(s). The unqualified
    # pg-${region}-backup name is legacy mode's; plugin mode names its own
    # pg-${region}-barman-backup (Klio's pg-${region}-klio-backup, if
    # present, is deleted in the Klio-specific block below)
    kubectl delete --context "${CONTEXT_NAME}" --ignore-not-found=true \
        cluster/pg-${region} \
        scheduledbackup/pg-${region}-backup \
        scheduledbackup/pg-${region}-barman-backup

    # Delete the PodMonitor if Prometheus CRDs are present
    if kubectl --context "${CONTEXT_NAME}" get crd podmonitors.monitoring.coreos.com &>/dev/null; then
        kubectl delete --context "${CONTEXT_NAME}" --ignore-not-found=true \
            podmonitor/pg-${region}-podmonitor
    fi

    # Delete the Klio Server, PluginConfiguration, and related cert-manager
    # resources, plus the Klio Operator itself, if Klio was deployed here
    if kubectl --context "${CONTEXT_NAME}" get crd servers.klio.cnpg.io &>/dev/null; then
        kubectl delete --context "${CONTEXT_NAME}" --ignore-not-found=true \
            scheduledbackup/pg-${region}-klio-backup \
            pluginconfiguration/klio-pg-${region} \
            server/klio-${region} \
            certificate/klio-${region}-tls \
            certificate/klio-${region}-ca \
            certificate/klio-${region}-client \
            issuer/klio-${region}-ca \
            issuer/klio-selfsigned-issuer \
            secret/klio-${region}-encryption

        if helm status klio-operator --kube-context "${CONTEXT_NAME}" --namespace cnpg-system &>/dev/null; then
            helm uninstall klio-operator \
                --kube-context "${CONTEXT_NAME}" --namespace cnpg-system
        fi

        # Helm does not remove CRDs on uninstall; delete them explicitly so a
        # later setup.sh run doesn't mistake their presence for an already
        # installed (but now absent) operator
        kubectl delete --context "${CONTEXT_NAME}" --ignore-not-found=true \
            crd/servers.klio.cnpg.io \
            crd/pluginconfigurations.klio.cnpg.io

        # The Klio Server's StatefulSet retains its PVCs by default. Deleting
        # them ensures a later setup.sh run starts from an empty tier1
        # repository instead of reattaching to one recorded against a
        # previous pg-${region} cluster's system ID (which fails WAL
        # streaming with an "invalid system ID" error).
        # The server/klio-${region} delete above only waits for that object
        # itself, not its owned StatefulSet/Pods, so the PVCs may still be
        # mounted here; bound the wait instead of risking an indefinite hang
        # on the pvc-protection finalizer (a leftover PVC just gets cleaned
        # up on the next teardown run).
        kubectl delete --context "${CONTEXT_NAME}" --ignore-not-found=true --timeout=60s \
            pvc -l klio.cnpg.io/klio-server=klio-${region}

        # Remove tier 2 backup data from the object store container
        ${CONTAINER_PROVIDER} exec objectstore-${region} rm -rf /data/klio
    fi

    # Delete the Barman ObjectStore CR, if the Barman Cloud Plugin CRDs are present
    if kubectl --context "${CONTEXT_NAME}" get crd objectstores.barmancloud.cnpg.io &>/dev/null; then
        kubectl delete --context "${CONTEXT_NAME}" --ignore-not-found=true \
            objectstore/objectstore-${region}
    fi

    # Delete Barman Cloud Plugin
    kubectl delete --context "${CONTEXT_NAME}" --ignore-not-found=true -f \
        "https://github.com/cloudnative-pg/plugin-barman-cloud/releases/download/${BARMAN_CLOUD_PLUGIN_VERSION}/manifest.yaml"

    # Delete cert-manager
    kubectl delete --context "${CONTEXT_NAME}" --ignore-not-found=true -f \
        "https://github.com/cert-manager/cert-manager/releases/download/${CERT_MANAGER_VERSION}/cert-manager.yaml"

    # Delete the ClusterImageCatalog
    kubectl delete --context "${CONTEXT_NAME}" --ignore-not-found=true -f \
        "${IMAGE_CATALOG_URL}"

    # Delete CNPG operator
    kubectl delete --context "${CONTEXT_NAME}" --ignore-not-found=true -f \
        "https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-${CNPG_RELEASE_BRANCH}/releases/cnpg-${CNPG_VERSION_BARE}.yaml"

    # Remove backup data from the object store container
    ${CONTAINER_PROVIDER} exec objectstore-${region} rm -rf /data/backups/pg-${region}

done
