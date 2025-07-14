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

set -xeu

git_repo_root=$(git rev-parse --show-toplevel)
kube_config_path=${git_repo_root}/k8s/kube-config.yaml
export KUBECONFIG=${kube_config_path}

# Deploy the Prometheus operator in both Kubernetes clusters
for region in eu us; do
    kubectl --context kind-k8s-${region} create ns prometheus-operator | true
    kubectl kustomize ${git_repo_root}/k8s/monitoring/prometheus-operator | \
    kubectl --context kind-k8s-${region} apply --force-conflicts --server-side -f -
done


# We make sure that monitoring workloads are deployed in the infrastructure node.
for context in eu us; do
    kubectl kustomize ${git_repo_root}/k8s/monitoring/prometheus-instance | \
        kubectl --context=kind-k8s-${region} apply --force-conflicts --server-side -f -
    kubectl --context=kind-k8s-${region} -n prometheus-operator \
      patch deployment prometheus-operator \
      --type='merge' \
      --patch='{"spec":{"template":{"spec":{"tolerations":[{"key":"node-role.kubernetes.io/infra","operator":"Exists","effect":"NoSchedule"}],"nodeSelector":{"node-role.kubernetes.io/infra":""}}}}}'
done


# Deploying Grafana operator
for context in eu us; do
    kubectl --context kind-k8s-${region} apply --force-conflicts --server-side \
      -f https://github.com/grafana/grafana-operator/releases/latest/download/kustomize-cluster_scoped.yaml
    kubectl --context kind-k8s-${region} -n grafana \
      patch deployment grafana-operator-controller-manager \
      --type='merge' \
      --patch='{"spec":{"template":{"spec":{"tolerations":[{"key":"node-role.kubernetes.io/infra","operator":"Exists","effect":"NoSchedule"}],"nodeSelector":{"node-role.kubernetes.io/infra":""}}}}}'
done

# Creating Grafana instance and dashboards
for context in eu us; do
    kubectl kustomize ${git_repo_root}/k8s/monitoring/grafana/ | \
      kubectl --context kind-k8s-${region} apply -f -
done

# Restart the operator
if kubectl get ns cnpg-system &> /dev/null
then
  kubectl rollout restart deployment -n cnpg-system cnpg-controller-manager
  kubectl rollout status deployment -n cnpg-system cnpg-controller-manager
fi
