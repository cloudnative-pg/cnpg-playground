#!/usr/bin/env bash
#
# This script deploys CloudNativePG in two regions and sets up a PostgreSQL
# example cluster using a distributed topology. The configuration leverages
# state synchronization with S3 object storage.
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

set -eux

git_repo_root=$(git rev-parse --show-toplevel)
kube_config_path=${git_repo_root}/k8s/kube-config.yaml
demo_yaml_path=${git_repo_root}/demo/yaml

# Ensure prerequisites are met
prereqs="kubectl kubectl-cnpg cmctl"
for cmd in $prereqs; do
   if [ -z "$(which $cmd)" ]; then
      echo "Missing command $cmd"
      exit 1
   fi
done

# Setup a separate Kubeconfig
cd "${git_repo_root}"
export KUBECONFIG=${kube_config_path}

# Begin deployment, one region at a time
for region in eu us; do

   # Deploy CloudNativePG operator (latest version, through the plugin)
   #kubectl cnpg install generate --control-plane | \
   curl -sSfL \
     https://raw.githubusercontent.com/cloudnative-pg/artifacts/main/manifests/operator-manifest.yaml | \
     kubectl --context kind-k8s-${region} apply -f - --server-side

   # Wait for CNPG deployment to complete
   kubectl --context kind-k8s-${region} rollout status deployment \
      -n cnpg-system cnpg-controller-manager

   # Deploy cert-manager
   kubectl apply --context kind-k8s-${region} -f \
      https://github.com/cert-manager/cert-manager/releases/latest/download/cert-manager.yaml

   # Wait for cert-manager deployment to complete
   kubectl rollout --context kind-k8s-${region} status deployment \
      -n cert-manager
   cmctl check api --wait=2m --context kind-k8s-${region}

   # Deploy Barman Cloud Plugin
   #kubectl apply --context kind-k8s-${region} -f \
   #   https://github.com/cloudnative-pg/plugin-barman-cloud/releases/latest/download/manifest.yaml
   kubectl apply --context kind-k8s-${region} -f \
      https://raw.githubusercontent.com/cloudnative-pg/plugin-barman-cloud/refs/heads/main/manifest.yaml

   # Wait for Barman Cloud Plugin deployment to complete
   kubectl rollout --context kind-k8s-${region} status deployment \
      -n cnpg-system barman-cloud

   # Create Barman object stores
   kubectl apply --context kind-k8s-${region} -f \
     ${demo_yaml_path}/object-stores

   # Create the Postgres cluster
   kubectl apply --context kind-k8s-${region} -f \
     ${demo_yaml_path}/${region}

   # Wait for the cluster to be ready
   kubectl wait --context kind-k8s-${region} \
     --timeout 30m \
     --for=condition=Ready cluster/pg-${region}

done
