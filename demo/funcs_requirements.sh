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
# Deployment of the CloudNativePG demo requirements: the CNPG operator,
# cert-manager, the Barman Cloud Plugin, and a ClusterImageCatalog (common
# extensions). Sourced by demo/setup.sh.
#

# Check whether a CRD exists in the given cluster context
check_crd_existence() {
    local context="$1"
    local crd="$2"
    kubectl --context "${context}" get crd "${crd}" &>/dev/null
}

# Deploy CloudNativePG, cert-manager, the Barman Cloud Plugin, and a
# ClusterImageCatalog into a single region, unless they are already
# installed there.
# Globals used: trunk, CERT_MANAGER_VERSION, CNPG_RELEASE_BRANCH,
# CNPG_VERSION_BARE, BARMAN_CLOUD_PLUGIN_VERSION, IMAGE_CATALOG_URL (set by
# scripts/common.sh and demo/setup.sh).
deploy_cnpg_requirements() {
    local region="$1"
    local context="$2"

    if check_crd_existence "${context}" clusters.postgresql.cnpg.io; then
        echo "ℹ️  CloudNativePG requirements already installed in region '${region}' (context: ${context});" \
            "skipping operator/cert-manager/Barman Cloud Plugin/ClusterImageCatalog installation."
        return
    fi

    if [ "${trunk}" -eq 1 ]; then
        # Deploy CloudNativePG operator (trunk - main branch)
        curl -sSfL \
            https://raw.githubusercontent.com/cloudnative-pg/artifacts/main/manifests/operator-manifest.yaml | \
            kubectl --context "${context}" apply -f - --server-side
    else
        # Deploy CloudNativePG operator (latest stable release)
        kubectl apply --server-side \
            --context "${context}" \
            -f "https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-${CNPG_RELEASE_BRANCH}/releases/cnpg-${CNPG_VERSION_BARE}.yaml"
    fi

    # Pin the operator to the control-plane node. The playground taints the
    # postgres nodes and reserves infra/app nodes for workloads, so the
    # control-plane is the natural home for the operator in this demo.
    kubectl --context "${context}" -n cnpg-system \
        patch deployment cnpg-controller-manager \
        --type='merge' \
        --patch='{"spec":{"template":{"spec":{"affinity":{"nodeAffinity":{"requiredDuringSchedulingIgnoredDuringExecution":{"nodeSelectorTerms":[{"matchExpressions":[{"key":"node-role.kubernetes.io/control-plane","operator":"Exists"}]}]}}},"tolerations":[{"key":"node-role.kubernetes.io/control-plane","operator":"Exists"}]}}}}'

    # Wait for CNPG deployment to complete
    kubectl --context "${context}" rollout status deployment \
        -n cnpg-system cnpg-controller-manager
    echo "📦 CloudNativePG: $(kubectl --context "${context}" get deployment cnpg-controller-manager \
        -n cnpg-system -o jsonpath='{.spec.template.spec.containers[0].image}')"

    # Deploy the ClusterImageCatalog with common extensions (requires the
    # postgresql.cnpg.io CRDs installed by the operator above)
    kubectl apply --context "${context}" -f "${IMAGE_CATALOG_URL}"
    echo "📦 ClusterImageCatalog: $(kubectl --context "${context}" get clusterimagecatalog \
        -o jsonpath='{.items[*].metadata.name}')"

    # Deploy cert-manager
    kubectl apply --context "${context}" -f \
        "https://github.com/cert-manager/cert-manager/releases/download/${CERT_MANAGER_VERSION}/cert-manager.yaml"

    # Wait for cert-manager deployment to complete
    kubectl rollout --context "${context}" status deployment \
        -n cert-manager
    cmctl check api --wait=2m --context "${context}"
    echo "📦 cert-manager: $(kubectl --context "${context}" get deployment cert-manager \
        -n cert-manager -o jsonpath='{.spec.template.spec.containers[0].image}')"

    if [ "${trunk}" -eq 1 ]; then
        # Deploy Barman Cloud Plugin (trunk)
        kubectl apply --context "${context}" -f \
            https://raw.githubusercontent.com/cloudnative-pg/plugin-barman-cloud/refs/heads/main/manifest.yaml
    else
        # Deploy Barman Cloud Plugin (latest stable)
        kubectl apply --context "${context}" -f \
            "https://github.com/cloudnative-pg/plugin-barman-cloud/releases/download/${BARMAN_CLOUD_PLUGIN_VERSION}/manifest.yaml"
    fi

    # Wait for Barman Cloud Plugin deployment to complete
    kubectl rollout --context "${context}" status deployment \
        -n cnpg-system barman-cloud
    echo "📦 Barman Cloud Plugin: $(kubectl --context "${context}" get deployment barman-cloud \
        -n cnpg-system -o jsonpath='{.spec.template.spec.containers[0].image}')"
}
