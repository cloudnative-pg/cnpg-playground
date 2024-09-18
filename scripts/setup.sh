#!/usr/bin/env bash
#
# This script sets up a simulated environment for deploying CloudNativePG
# across two regions: Europe and the USA. Each region includes its own
# Kubernetes cluster and a dedicated object storage system for backups,
# using an external MinIO instance in Docker to emulate an S3-compatible
# object store.
#
# The Kubernetes clusters in each region consist of multiple nodes, each with
# specialized roles—managing the control plane, handling infrastructure workloads,
# hosting applications, and running PostgreSQL databases.
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

set -eu

# MinIO settings and credentials
MINIO_IMAGE="${MINIO_IMAGE:-quay.io/minio/minio:RELEASE.2024-09-13T20-26-02Z}"
MINIO_EU_ROOT_USER="${MINIO_EU_ROOT_USER:-cnpg-eu}"
MINIO_EU_ROOT_PASSWORD="${MINIO_EU_ROOT_PASSWORD:-postgres5432-eu}"
MINIO_US_ROOT_USER="${MINIO_US_ROOT_USER:-cnpg-us}"
MINIO_US_ROOT_PASSWORD="${MINIO_US_ROOT_PASSWORD:-postgres5432-us}"

# Ensure prerequisites are met
prereqs="kind kubectl git docker"
for cmd in $prereqs; do
   if [ -z "$(which $cmd)" ]; then
      echo "Missing command $cmd"
      exit 1
   fi
done

git_repo_root=$(git rev-parse --show-toplevel)
kube_config_path=${git_repo_root}/k8s/kube-config.yaml
kind_config_path=${git_repo_root}/k8s/kind-cluster.yaml

# Setup a separate Kubeconfig
cd "${git_repo_root}"
export KUBECONFIG=${kube_config_path}

# Setup the object stores
docker run \
   --name minio-eu \
	 -d \
   -v "${git_repo_root}/minio-eu:/data" \
   -e "MINIO_ROOT_USER=$MINIO_EU_ROOT_USER" \
   -e "MINIO_ROOT_PASSWORD=$MINIO_EU_ROOT_PASSWORD" \
   -u $(id -u):$(id -g) \
   ${MINIO_IMAGE} server /data --console-address ":9001"

docker run \
   --name minio-us \
	 -d \
   -v "${git_repo_root}/minio-us:/data" \
   -e "MINIO_ROOT_USER=$MINIO_US_ROOT_USER" \
   -e "MINIO_ROOT_PASSWORD=$MINIO_US_ROOT_PASSWORD" \
   -u $(id -u):$(id -g) \
   ${MINIO_IMAGE} server /data --console-address ":9001"

# Setup the EU Kind Cluster
kind create cluster --config ${kind_config_path} --name k8s-eu
# The `node-role.kubernetes.io` label must be set after the node have been created
kubectl label node -l postgres.node.kubernetes.io node-role.kubernetes.io/postgres=
kubectl label node -l infra.node.kubernetes.io node-role.kubernetes.io/infra=
kubectl label node -l app.node.kubernetes.io node-role.kubernetes.io/app=

# Setup the US Kind Cluster
kind create cluster --config ${kind_config_path} --name k8s-us
# The `node-role.kubernetes.io` label must be set after the node have been created
kubectl label node -l postgres.node.kubernetes.io node-role.kubernetes.io/postgres=
kubectl label node -l infra.node.kubernetes.io node-role.kubernetes.io/infra=
kubectl label node -l app.node.kubernetes.io node-role.kubernetes.io/app=

docker network connect kind minio-eu
docker network connect kind minio-us

# Create the secrets for MinIO
for context in kind-k8s-eu kind-k8s-us; do
   kubectl create secret generic minio-eu \
      --context $context \
      --from-literal=ACCESS_KEY_ID="$MINIO_EU_ROOT_USER" \
      --from-literal=ACCESS_SECRET_KEY="$MINIO_EU_ROOT_PASSWORD"

   kubectl create secret generic minio-us \
      --context $context \
      --from-literal=ACCESS_KEY_ID="$MINIO_US_ROOT_USER" \
      --from-literal=ACCESS_SECRET_KEY="$MINIO_US_ROOT_PASSWORD"
done

./scripts/info.sh
