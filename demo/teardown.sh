#!/usr/bin/env bash
#
# This script tears down the demo example for CloudNativePG.
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

set -ux

git_repo_root=$(git rev-parse --show-toplevel)

# Source the common setup script
source ${git_repo_root}/scripts/common.sh

kube_config_path=${git_repo_root}/k8s/kube-config.yaml
demo_yaml_path=${git_repo_root}/demo/yaml

# Setup a separate Kubeconfig
cd "${git_repo_root}"
export KUBECONFIG=${kube_config_path}

# Delete deployment, one region at a time
for region in eu us; do

   CONTEXT_NAME=$(get_cluster_context "${region}")

   # Delete the Postgres cluster
   kubectl delete --context ${CONTEXT_NAME} --ignore-not-found=true -f \
     ${demo_yaml_path}/${region}

   # Delete Barman object stores
   kubectl delete --context ${CONTEXT_NAME} --ignore-not-found=true -f \
     ${demo_yaml_path}/object-stores

   # Delete Barman Cloud Plugin
   kubectl delete --context ${CONTEXT_NAME} --ignore-not-found=true -f \
      https://github.com/cloudnative-pg/plugin-barman-cloud/releases/latest/download/manifest.yaml

   # Delete cert-manager
   kubectl delete --context ${CONTEXT_NAME} --ignore-not-found=true -f \
      https://github.com/cert-manager/cert-manager/releases/latest/download/cert-manager.yaml

   # Delete CNPG operator
   kubectl cnpg install generate --control-plane | \
     kubectl --context ${CONTEXT_NAME} delete --ignore-not-found=true -f -

   # Remove backup data
   docker exec minio-${region} rm -rf /data/backups/pg-${region}

done
