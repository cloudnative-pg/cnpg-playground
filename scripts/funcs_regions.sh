#!/usr/bin/env bash
#
# This script contains the functions used to set the ${REGIONS} variable.
# set_regions() --> if called without an argument, EU and US are set
#                   otherwise the arguments.
#
# detect_running_regions() -->  if called without an argument, the running
#                               CNPG-Playground Kind clusters regions are set
#                               otherwise the arguments.
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

# --- Set regions ---
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
detect_running_regions() {
    if [ $# -gt 0 ]; then
        REGIONS=("$@")
        echo "🎯 Targeting specified regions: ${REGIONS[*]}"
    else
        echo "🔎 Auto-detecting all active playground regions..."
        # The '|| true' prevents the script from exiting if grep finds no matches.
        REGIONS=($(kind get clusters | grep "^${K8S_BASE_NAME}" | sed "s/^${K8S_BASE_NAME}//" || true))
        if [ ${#REGIONS[@]} -gt 0 ]; then
            echo "✅ Found regions: ${REGIONS[*]}"
	else
            echo "✅ No region detected"
	fi
    fi
}

# Helper function that builds the name of the cluster in a standard way given the region
get_cluster_name() {
    local region="$1"
    echo "${K8S_BASE_NAME}${region}"
}

# Helper function that builds the name of the context in a standard way given the region
get_cluster_context() {
    local region="$1"
    echo "${K8S_CONTEXT_PREFIX}${K8S_BASE_NAME}${region}"
}
