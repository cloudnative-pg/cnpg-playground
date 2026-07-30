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
# Helper functions used to render the demo's per-region YAML. Sourced by
# demo/setup.sh.
#

set -euo pipefail

# --- Format a duration in seconds as "Xm YYs" ---
format_duration() {
    local s=$1
    printf "%dm %02ds" $((s / 60)) $((s % 60))
}

# Return the replica source for a given region in the circular chain.
# For a ring [r0, r1, ..., rN-1]:
#   source(r0) = rN-1  (the primary wraps around to the last region)
#   source(ri) = r(i-1)
get_source_region() {
    local target="$1"
    shift
    local regions=("$@")
    local num_regions=${#regions[@]}
    local prev="${regions[$((num_regions - 1))]}"
    local r
    for r in "${regions[@]}"; do
        if [ "${r}" = "${target}" ]; then
            echo "${prev}"
            return
        fi
        prev="${r}"
    done
}
