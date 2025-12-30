#!/usr/bin/env bash
#
# This script contains common variables and functions shared by the setup,
# info, and cleanup scripts for the CloudNativePG playground.
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

set -euo pipefail

# --- Common Configuration ---
# Kind base name for clusters
# K8S_BASE_NAME=${K8S_NAME:-k8s}

# MinIO Configuration
MINIO_IMAGE="${MINIO_IMAGE:-quay.io/minio/minio:RELEASE.2025-09-07T16-13-09Z}"
MINIO_BASE_NAME="${MINIO_BASE_NAME:-minio}"
MINIO_BASE_PORT=${MINIO_BASE_PORT:-9001}
MINIO_ROOT_USER="${MINIO_ROOT_USER:-cnpg}"
MINIO_ROOT_PASSWORD="${MINIO_ROOT_PASSWORD:-Cl0udNativePGRocks}"

# --- Common Prerequisite Checks ---
REQUIRED_COMMANDS="kind kubectl git grep sed"
for cmd in $REQUIRED_COMMANDS; do
    if ! command -v "$cmd" &> /dev/null; then
        echo "❌ Error: Missing required command: $cmd"
        exit 1
    fi
done

# --- Common Setup ---
# Find a supported container provider
CONTAINER_PROVIDER=""
for provider in docker podman; do
    if command -v "$provider" &> /dev/null; then
        CONTAINER_PROVIDER=$provider
        break
    fi
done

if [ -z "${CONTAINER_PROVIDER:-}" ]; then
    echo "❌ Error: Missing container provider. Supported providers are: docker, podman"
    exit 1
fi

# Determine project root and kubeconfig path
GIT_REPO_ROOT=$(git rev-parse --show-toplevel)
KUBE_CONFIG_PATH="${GIT_REPO_ROOT}/k8s/kube-config.yaml"

# source funcs_regions.sh
source $(git rev-parse --show-toplevel)/scripts/funcs_regions.sh
