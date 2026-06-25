#!/usr/bin/env bash
##
## Copyright © contributors to CloudNativePG, established as
## CloudNativePG a Series of LF Projects, LLC.
##
## Licensed under the Apache License, Version 2.0 (the "License");
## you may not use this file except in compliance with the License.
## You may obtain a copy of the License at
##
##     http://www.apache.org/licenses/LICENSE-2.0
##
## Unless required by applicable law or agreed to in writing, software
## distributed under the License is distributed on an "AS IS" BASIS,
## WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
## See the License for the specific language governing permissions and
## limitations under the License.
##
## SPDX-License-Identifier: Apache-2.0
##

#
# This script contains common variables and functions shared by the setup,
# info, and cleanup scripts for the CloudNativePG playground.
#

set -euo pipefail

# --- Common Configuration ---
# Kind base name for clusters
K8S_CONTEXT_PREFIX=${K8S_CONTEXT_PREFIX-kind-}
K8S_BASE_NAME=${K8S_NAME-k8s-}

# RustFS Configuration
# renovate: datasource=docker depName=rustfs/rustfs
RUSTFS_VERSION="${RUSTFS_VERSION:-1.0.0-beta.1}"
RUSTFS_IMAGE="${RUSTFS_IMAGE:-rustfs/rustfs:${RUSTFS_VERSION}}"
RUSTFS_BASE_NAME="${RUSTFS_BASE_NAME:-objectstore}"
RUSTFS_BASE_PORT=${RUSTFS_BASE_PORT:-9001}
RUSTFS_ROOT_USER="${RUSTFS_ROOT_USER:-cnpg}"
RUSTFS_ROOT_PASSWORD="${RUSTFS_ROOT_PASSWORD:-Cl0udNativePGRocks}"

# --- Common Prerequisite Checks ---
REQUIRED_COMMANDS="kind kubectl grep sed"
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
REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
KUBE_CONFIG_PATH="${REPO_ROOT}/k8s/kube-config.yaml"

# Demo deployment versions
# renovate: datasource=github-releases depName=cert-manager/cert-manager
CERT_MANAGER_VERSION="${CERT_MANAGER_VERSION:-v1.20.3}"
# renovate: datasource=github-releases depName=cloudnative-pg/cloudnative-pg
CNPG_VERSION="${CNPG_VERSION:-v1.29.1}"
# Derived: bare version and release branch suffix (e.g. v1.29.0 -> 1.29.0, 1.29)
CNPG_VERSION_BARE="${CNPG_VERSION#v}"
CNPG_RELEASE_BRANCH="${CNPG_VERSION_BARE%.*}"
# renovate: datasource=github-releases depName=cloudnative-pg/plugin-barman-cloud
BARMAN_CLOUD_PLUGIN_VERSION="${BARMAN_CLOUD_PLUGIN_VERSION:-v0.13.0}"
# renovate: datasource=github-releases depName=grafana/grafana-operator
GRAFANA_OPERATOR_VERSION="${GRAFANA_OPERATOR_VERSION:-v5.24.0}"

source "${REPO_ROOT}/scripts/funcs_regions.sh"
