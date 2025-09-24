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

K8S_BASE_NAME=${K8S_NAME:-k8s}
git_repo_root=$(git rev-parse --show-toplevel)
kube_config_path=${git_repo_root}/k8s/kube-config.yaml
demo_yaml_path=${git_repo_root}/demo/yaml

legacy=
if [ "${LEGACY:-}" = "true" ]; then
   legacy="-legacy"
fi

trunk=0
if [ "${TRUNK:-}" = "true" ]; then
   trunk=1
fi

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

   if [ $trunk -eq 1 ]
   then
     # Deploy CloudNativePG operator (trunk - main branch)
     curl -sSfL \
       https://raw.githubusercontent.com/cloudnative-pg/artifacts/main/manifests/operator-manifest.yaml | \
       kubectl --context kind-${K8S_BASE_NAME}-${region} apply -f - --server-side
   else
     # Deploy CloudNativePG operator (latest version, through the plugin)
     kubectl cnpg install generate --control-plane | \
       kubectl --context kind-${K8S_BASE_NAME}-${region} apply -f - --server-side
   fi

   # Wait for CNPG deployment to complete
   kubectl --context kind-${K8S_BASE_NAME}-${region} rollout status deployment \
      -n cnpg-system cnpg-controller-manager

   # Deploy cert-manager
   kubectl apply --context kind-${K8S_BASE_NAME}-${region} -f \
      https://github.com/cert-manager/cert-manager/releases/latest/download/cert-manager.yaml

   # Wait for cert-manager deployment to complete
   kubectl rollout --context kind-${K8S_BASE_NAME}-${region} status deployment \
      -n cert-manager
   cmctl check api --wait=2m --context kind-${K8S_BASE_NAME}-${region}

   if [ $trunk -eq 1 ]
   then
     # Deploy Barman Cloud Plugin (trunk)
     kubectl apply --context kind-${K8S_BASE_NAME}-${region} -f \
       https://raw.githubusercontent.com/cloudnative-pg/plugin-barman-cloud/refs/heads/main/manifest.yaml
   else
     # Deploy Barman Cloud Plugin (latest stable)
     kubectl apply --context kind-${K8S_BASE_NAME}-${region} -f \
        https://github.com/cloudnative-pg/plugin-barman-cloud/releases/latest/download/manifest.yaml
   fi

   # Wait for Barman Cloud Plugin deployment to complete
   kubectl rollout --context kind-${K8S_BASE_NAME}-${region} status deployment \
      -n cnpg-system barman-cloud

   # Create Barman object stores
   kubectl apply --context kind-${K8S_BASE_NAME}-${region} -f \
     ${demo_yaml_path}/object-stores

   # Create the Postgres cluster
   kubectl apply --context kind-${K8S_BASE_NAME}-${region} -f \
     ${demo_yaml_path}/${region}/pg-${region}${legacy}.yaml

   # Wait for the cluster to be ready
   kubectl wait --context kind-${K8S_BASE_NAME}-${region} \
     --timeout 30m \
     --for=condition=Ready cluster/pg-${region}

done
