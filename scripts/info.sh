#!/usr/bin/env bash
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

set -eu

git_repo_root=$(git rev-parse --show-toplevel)
kube_config_path=${git_repo_root}/k8s/kube-config.yaml

cat <<EOF
To access the playground clusters, ensure you set the following environment
variable:

export KUBECONFIG=${kube_config_path}

To switch between clusters, use the commands below:

kubectl config use-context kind-k8s-eu
kubectl config use-context kind-k8s-us

To check which cluster you’re currently connected to:

kubectl config current-context
EOF
