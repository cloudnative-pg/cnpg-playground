#!/usr/bin/env bash
#
# This script sets up the Prometheus / Grafana operator
# Without option it searches for cnpg-playground kind clusters in your environmen
# and deploy / setup the operators. 
# To setup monitoring for a specific region, use the region as option.
#
#
# Copyright The CloudNativePG Contributors
#
# Setup a Prometheus/Grafana stack on infrastructure nodes
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
REGIONS=()
if [ $# -gt 0 ]; then
    REGIONS=("$@")
    echo "🎯 Targeting specified regions for monitoring setup: ${REGIONS[*]}"
else
    echo "🔎 Auto-detecting all active playground regions for monitoring setup..."
    # The '|| true' prevents the script from exiting if grep finds no matches.
    REGIONS=($(kind get clusters | grep "^${K8S_BASE_NAME}-" | sed "s/^${K8S_BASE_NAME}-//" || true))
fi

# Add a target port for the port-forward, the port will be incremeted by 1 for each region
port=3000

for region in "${REGIONS[@]}"; do
    echo "-------------------------------------------------------------"
    echo " 🔥 Provisioning Prometheus resources for region: ${region}"
    echo "-------------------------------------------------------------"

    K8S_CLUSTER_NAME="${K8S_BASE_NAME}-${region}"

# Deploy the Prometheus operator in the playground Kubernetes clusters
    kubectl --context kind-${K8S_CLUSTER_NAME} create ns prometheus-operator || true
    kubectl kustomize ${GIT_REPO_ROOT}/monitoring/prometheus-operator | \
      kubectl --context kind-${K8S_CLUSTER_NAME} apply --force-conflicts --server-side -f -

# We make sure that monitoring workloads are deployed in the infrastructure node.
    kubectl kustomize ${GIT_REPO_ROOT}/monitoring/prometheus-instance | \
        kubectl --context=kind-${K8S_CLUSTER_NAME} apply --force-conflicts --server-side -f -
    kubectl --context=kind-${K8S_CLUSTER_NAME} -n prometheus-operator \
      patch deployment prometheus-operator \
      --type='merge' \
      --patch='{"spec":{"template":{"spec":{"tolerations":[{"key":"node-role.kubernetes.io/infra","operator":"Exists","effect":"NoSchedule"}],"nodeSelector":{"node-role.kubernetes.io/infra":""}}}}}'

    echo "-------------------------------------------------------------"
    echo " 📈 Provisioning Grafana resources for region: ${region}"
    echo "-------------------------------------------------------------"

# Deploying Grafana operator
    kubectl --context kind-${K8S_CLUSTER_NAME} apply --force-conflicts --server-side \
      -f https://github.com/grafana/grafana-operator/releases/latest/download/kustomize-cluster_scoped.yaml
    kubectl --context kind-${K8S_CLUSTER_NAME} -n grafana \
      patch deployment grafana-operator-controller-manager \
      --type='merge' \
      --patch='{"spec":{"template":{"spec":{"tolerations":[{"key":"node-role.kubernetes.io/infra","operator":"Exists","effect":"NoSchedule"}],"nodeSelector":{"node-role.kubernetes.io/infra":""}}}}}'

# Creating Grafana instance and dashboards
    kubectl kustomize ${GIT_REPO_ROOT}/monitoring/grafana/ | \
      kubectl --context kind-${K8S_CLUSTER_NAME} apply -f -

# Restart the operator
if kubectl get ns cnpg-system &> /dev/null
then
  kubectl rollout restart deployment -n cnpg-system cnpg-controller-manager
  kubectl rollout status deployment -n cnpg-system cnpg-controller-manager
fi

    echo "-----------------------------------------------------------------------------------------------------------------"
    echo " ⏩ To forward the Grafana service for region: ${region} to your localhost"
    echo " Wait for the Grafana service to be created and then forward the service"
    echo ""
    echo " kubectl port-forward service/grafana-service ${port}:3000 -n grafana --context kind-k8s-${region}"
    echo ""
    echo " You can then connect to the Grafana GUI using"
    echo " http://localhost:${port}"
    echo " The default password for the user admin is 'admin'. You will be prompted to change the password on the first login."
    echo "-----------------------------------------------------------------------------------------------------------------"    
    # increment target port by 1
    ((port++))
done
