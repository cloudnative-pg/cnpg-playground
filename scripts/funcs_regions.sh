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
K8S_BASE_NAME=${K8S_NAME:-k8s}

# --- Set regions ---
# if called with an argument, $REGIONS is set to it's value
# if no argument is provided, $REGIONS is set to the defualt regions "eu" and "us"
set_regions() {
    if [ $# -eq 0 ]; then
        REGIONS=("eu" "us")
        echo "❌ No region provided, using the default regions "eu" "us"..."
    else
        REGIONS=("$@")
        echo "🔎 Using the provided regions: ${REGIONS[*]}"
    fi
}

# --- detect regions ---
# if called with an argument, $REGIONS is set to it's value
# if no argument is provided, $REGIONS is set to the running kind clusters
detect_running_regions() {
    if [ $# -gt 0 ]; then
        REGIONS=("$@")
        echo "🎯 Targeting specified regions: ${REGIONS[*]}"
    else
        echo "🔎 Auto-detecting all active playground regions..."
        # The '|| true' prevents the script from exiting if grep finds no matches.
        REGIONS=($(kind get clusters | grep "^${K8S_BASE_NAME}-" | sed "s/^${K8S_BASE_NAME}-//" || true))
        echo "✅ Found regions: ${REGIONS[*]}"
    fi
}