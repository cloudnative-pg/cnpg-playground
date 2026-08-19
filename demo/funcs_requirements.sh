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
# cert-manager, a ClusterImageCatalog (common extensions), and, optionally,
# the Barman Cloud Plugin and/or the Klio Operator. Sourced by
# demo/setup.sh.
#

# Check whether a CRD exists in the given cluster context
check_crd_existence() {
    local context="$1"
    local crd="$2"
    kubectl --context "${context}" get crd "${crd}" &>/dev/null
}

# Deploy CloudNativePG, cert-manager, a ClusterImageCatalog, and (unless
# BARMAN_CLOUD_PLUGIN=false) the Barman Cloud Plugin into a single region, unless they
# are already installed there.
# Globals used: trunk, barman_cloud_plugin, CERT_MANAGER_VERSION, CNPG_RELEASE_BRANCH,
# CNPG_VERSION_BARE, BARMAN_CLOUD_PLUGIN_VERSION, IMAGE_CATALOG_URL (set by
# scripts/common.sh and demo/setup.sh).
deploy_cnpg_requirements() {
    local region="$1"
    local context="$2"

    if check_crd_existence "${context}" clusters.postgresql.cnpg.io; then
        echo "ℹ️  CloudNativePG requirements already installed in region '${region}' (context: ${context});" \
            "skipping operator/cert-manager/backup plugin(s)/ClusterImageCatalog installation."
        return
    fi

    # shellcheck disable=SC2154 # trunk is set by demo/setup.sh
    if [ "${trunk}" -eq 1 ]; then
        # Deploy CloudNativePG operator (trunk - main branch)
        curl -sSfL \
            https://raw.githubusercontent.com/cloudnative-pg/artifacts/main/manifests/operator-manifest.yaml |
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

    # shellcheck disable=SC2154 # barman_cloud_plugin is set by demo/setup.sh
    if ${barman_cloud_plugin}; then
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
    else
        echo "⏭️  Skipping Barman Cloud Plugin installation (BARMAN_CLOUD_PLUGIN=false)."
    fi
}

# Deploy the Klio Operator (multi-tier backup and recovery plugin for
# CloudNativePG) via its Helm chart, into the same namespace as the
# CloudNativePG operator, unless it is already installed in this region.
# Requires cert-manager, which deploy_cnpg_requirements installs beforehand.
# Globals used: CONTAINER_PROVIDER, KLIO_VERSION, KLIO_CHART (set by
# scripts/common.sh).
deploy_klio_requirements() {
    local region="$1"
    local context="$2"

    # RustFS (unlike the Barman Cloud Plugin's S3 client) does not create a
    # bucket on first write, and Klio's tier2 client requires one to already
    # exist. A dedicated bucket keeps Klio's data separate from the Barman
    # Cloud Plugin's "backups" bucket; demo/teardown.sh removes it again.
    "${CONTAINER_PROVIDER}" exec "objectstore-${region}" mkdir -p /data/klio

    if check_crd_existence "${context}" servers.klio.cnpg.io; then
        echo "ℹ️  Klio Operator already installed in region '${region}' (context: ${context});" \
            "skipping installation."
        return
    fi

    # No CRDs are installed by cnpg-playground's Prometheus setup by default
    # (see monitoring/setup.sh), so disable the chart's ServiceMonitor unless
    # the Prometheus Operator CRDs are already present.
    local prometheus_enable=false
    if check_crd_existence "${context}" servicemonitors.monitoring.coreos.com; then
        prometheus_enable=true
    fi

    # Pin the operator to the control-plane node, same as the CNPG operator
    # above. Unlike the CNPG operator (applied via plain manifest, then
    # patched), the Klio Operator chart exposes affinity/tolerations as
    # native values, so they're set at install time instead.
    helm install klio-operator "${KLIO_CHART}" \
        --version "${KLIO_VERSION#v}" \
        --kube-context "${context}" \
        --namespace cnpg-system \
        --set "prometheus.enable=${prometheus_enable}" \
        --set-json 'controllerManager.affinity={"nodeAffinity":{"requiredDuringSchedulingIgnoredDuringExecution":{"nodeSelectorTerms":[{"matchExpressions":[{"key":"node-role.kubernetes.io/control-plane","operator":"Exists"}]}]}}}' \
        --set-json 'controllerManager.tolerations=[{"key":"node-role.kubernetes.io/control-plane","operator":"Exists"}]' \
        --wait --timeout 5m

    echo "📦 Klio Operator: $(kubectl --context "${context}" get deployment klio-operator-controller-manager \
        -n cnpg-system -o jsonpath='{.spec.template.spec.containers[0].image}')"
}
