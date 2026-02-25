#!/usr/bin/env bash
#
# This script installs and configures the Prometheus and Grafana operators.
# When run without arguments, it automatically detects all cnpg-playground
# Kind clusters in your environment and deploys the monitoring stack for each.
# To install monitoring for specific regions only, pass the region names as arguments.
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
detect_running_regions "$@"

# Add a target port for the port-forward, the port will be incremeted by 1 for each region
port=3001

for region in "${REGIONS[@]}"; do
    echo "-------------------------------------------------------------"
    echo " 🔥 Provisioning Prometheus resources for region: ${region}"
    echo "-------------------------------------------------------------"

    K8S_CLUSTER_NAME=$(get_cluster_name "${region}")
    CONTEXT_NAME=$(get_cluster_context "${region}")

    echo "🔥 Deploying Prometheus operator..."
    kubectl --context ${CONTEXT_NAME} create ns prometheus-operator || true
    kubectl kustomize ${GIT_REPO_ROOT}/monitoring/prometheus-operator | \
      kubectl --context ${CONTEXT_NAME} apply --force-conflicts --server-side -f -
    
    echo "⏳ Waiting for Prometheus CRDs to be ready..."
    kubectl --context ${CONTEXT_NAME} wait --for condition=established --timeout=60s \
      crd/servicemonitors.monitoring.coreos.com crd/prometheusrules.monitoring.coreos.com || true

    echo "📊 Deploying kube-state-metrics..."
    kubectl kustomize ${GIT_REPO_ROOT}/monitoring/kube-state-metrics | \
      kubectl --context ${CONTEXT_NAME} apply --force-conflicts --server-side -f -

    echo "🖥️  Deploying node-exporter..."
    kubectl kustomize ${GIT_REPO_ROOT}/monitoring/node-exporter | \
      kubectl --context ${CONTEXT_NAME} apply --force-conflicts --server-side -f -

    echo "🔧 Deploying Prometheus instance and recording rules via kustomize..."
    kubectl kustomize ${GIT_REPO_ROOT}/monitoring/prometheus-instance | \
        kubectl --context=${CONTEXT_NAME} apply --force-conflicts --server-side -f -
    kubectl --context=${CONTEXT_NAME} -n prometheus-operator \
      patch deployment prometheus-operator \
      --type='merge' \
      --patch='{"spec":{"template":{"spec":{"tolerations":[{"key":"node-role.kubernetes.io/infra","operator":"Exists","effect":"NoSchedule"}],"nodeSelector":{"node-role.kubernetes.io/infra":""}}}}}'

    echo "🔧 Setting up kubelet metrics scraping..."
    kubectl --context=${CONTEXT_NAME} apply -f ${GIT_REPO_ROOT}/monitoring/prometheus-instance/servicemonitor-kubelet.yaml
    NODE_IPS=$(kubectl --context ${CONTEXT_NAME} get nodes -o jsonpath='{range .items[*]}{.status.addresses[?(@.type=="InternalIP")].address}{"\n"}{end}')
    cat <<EOF | kubectl --context=${CONTEXT_NAME} apply -f -
apiVersion: v1
kind: Endpoints
metadata:
  name: kubelet
  namespace: kube-system
  labels:
    app.kubernetes.io/name: kubelet
subsets:
- addresses:
$(for ip in ${NODE_IPS}; do echo "  - ip: ${ip}"; done)
  ports:
  - name: https-metrics
    port: 10250
    protocol: TCP
EOF

    echo "-------------------------------------------------------------"
    echo " 📈 Provisioning Grafana resources for region: ${region}"
    echo "-------------------------------------------------------------"

# Deploying Grafana operator
    # Pinned to v5.21.3 due to CRD validation bug in v5.21.4+
    kubectl --context ${CONTEXT_NAME} apply --force-conflicts --server-side \
      -f https://github.com/grafana/grafana-operator/releases/download/v5.21.3/kustomize-cluster_scoped.yaml
    kubectl --context ${CONTEXT_NAME} -n grafana \
      patch deployment grafana-operator-controller-manager \
      --type='merge' \
      --patch='{"spec":{"template":{"spec":{"tolerations":[{"key":"node-role.kubernetes.io/infra","operator":"Exists","effect":"NoSchedule"}],"nodeSelector":{"node-role.kubernetes.io/infra":""}}}}}'

# Creating Grafana instance and dashboards
    kubectl kustomize ${GIT_REPO_ROOT}/monitoring/grafana/ | \
      kubectl --context ${CONTEXT_NAME} apply -f -

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
    echo " kubectl port-forward service/grafana-service ${port}:3000 -n grafana --context ${CONTEXT_NAME}"
    echo ""
    echo " You can then connect to the Grafana GUI using"
    echo " http://localhost:${port}"
    echo " The default password for the user admin is 'admin'. You will be prompted to change the password on the first login."
    echo "-----------------------------------------------------------------------------------------------------------------"    
    # increment target port by 1
    ((port++))
done
