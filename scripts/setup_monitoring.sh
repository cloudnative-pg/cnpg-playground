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

set -eu

git_repo_root=$(git rev-parse --show-toplevel)
kube_config_path=${git_repo_root}/k8s/kube-config.yaml
export KUBECONFIG=${kube_config_path}

# We need to deploy the Prometheus operator in both regions
for context in kind-k8s-eu kind-k8s-us; do
    kubectl --context $context create ns prometheus-operator | true
    kustomize build ${git_repo_root}/k8s/monitoring/prometheus-operator | \
    kubectl --context $context apply --force-conflicts --server-side=true -f -
done


# There's dedicated nodes for infrastructure, we make sure that every reosurce
# is attached to those nodes
for context in kind-k8s-eu kind-k8s-us; do
    kustomize build ${git_repo_root}/k8s/monitoring/prometheus-instance | \
        kubectl --context=$context apply --force-conflicts --server-side=true -f - 
    kubectl --context=$context -n prometheus-operator \
            patch deployment prometheus-operator \
            --type='merge' --patch='{"spec":{"template":{"spec":{"tolerations":[{"key":"node-role.kubernetes.io/infra","operator":"Exists","effect":"NoSchedule"}],"nodeSelector":{"node-role.kubernetes.io/infra":""}}}}}'
done


# Deploying Grafana operator
for context in kind-k8s-eu kind-k8s-us; do
    kubectl --context $context apply --force-conflicts --server-side=true -f https://github.com/grafana/grafana-operator/releases/latest/download/kustomize-cluster_scoped.yaml
done

# Creating Granfa instance and dashboards
for context in kind-k8s-eu kind-k8s-us; do
    kustomize build ${git_repo_root}/k8s/monitoring/grafana/ | \
    kubectl --context $context apply -f -
done
