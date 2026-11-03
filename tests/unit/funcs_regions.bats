#!/usr/bin/env bats
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
# Unit tests for scripts/funcs_regions.sh. Sources the file directly (not
# scripts/common.sh), so K8S_BASE_NAME/K8S_CONTEXT_PREFIX are set by hand and
# there's no dependency on any external tool beyond bash builtins.
#

setup() {
    repo_root="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    # shellcheck source=scripts/funcs_regions.sh
    source "${repo_root}/scripts/funcs_regions.sh"
    K8S_BASE_NAME="k8s-"
    K8S_CONTEXT_PREFIX="kind-"
}

@test "set_regions with no args defaults to eu na" {
    set_regions
    [ "${#REGIONS[@]}" -eq 2 ]
    [ "${REGIONS[0]}" = "eu" ]
    [ "${REGIONS[1]}" = "na" ]
}

@test "set_regions with explicit args passes them through" {
    set_regions us ap
    [ "${#REGIONS[@]}" -eq 2 ]
    [ "${REGIONS[0]}" = "us" ]
    [ "${REGIONS[1]}" = "ap" ]
}

@test "get_cluster_name builds the name from K8S_BASE_NAME + region" {
    [ "$(get_cluster_name eu)" = "k8s-eu" ]
}

@test "get_cluster_context builds the context from prefix + base name + region" {
    [ "$(get_cluster_context eu)" = "kind-k8s-eu" ]
}

@test "detect_running_regions with explicit args passes them through without calling kind" {
    detect_running_regions us ap
    [ "${#REGIONS[@]}" -eq 2 ]
    [ "${REGIONS[0]}" = "us" ]
    [ "${REGIONS[1]}" = "ap" ]
}

@test "detect_running_regions auto-detects matching clusters, stripping the base-name prefix" {
    kind() { printf 'k8s-eu\nk8s-na\nsome-other-cluster\n'; }
    detect_running_regions
    [ "${#REGIONS[@]}" -eq 2 ]
    [ "${REGIONS[0]}" = "eu" ]
    [ "${REGIONS[1]}" = "na" ]
}

@test "detect_running_regions finds no regions when nothing matches" {
    kind() { printf 'some-other-cluster\n'; }
    detect_running_regions
    [ "${#REGIONS[@]}" -eq 0 ]
}
