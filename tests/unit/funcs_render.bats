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
# Unit tests for demo/funcs_render.sh.
#

setup() {
    repo_root="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    # shellcheck source=demo/funcs_render.sh
    source "${repo_root}/demo/funcs_render.sh"
}

@test "format_duration formats zero seconds" {
    [ "$(format_duration 0)" = "0m 00s" ]
}

@test "format_duration formats under a minute" {
    [ "$(format_duration 5)" = "0m 05s" ]
}

@test "format_duration formats just over a minute" {
    [ "$(format_duration 61)" = "1m 01s" ]
}

@test "format_duration formats exactly one hour as 60 minutes" {
    [ "$(format_duration 3600)" = "60m 00s" ]
}

@test "get_source_region on a single-region ring wraps to itself" {
    [ "$(get_source_region eu eu)" = "eu" ]
}

@test "get_source_region on a two-region ring" {
    [ "$(get_source_region eu eu na)" = "na" ]
    [ "$(get_source_region na eu na)" = "eu" ]
}

@test "get_source_region on a four-region ring wraps the first region to the last" {
    [ "$(get_source_region eu eu na us ap)" = "ap" ]
    [ "$(get_source_region na eu na us ap)" = "eu" ]
    [ "$(get_source_region us eu na us ap)" = "na" ]
    [ "$(get_source_region ap eu na us ap)" = "us" ]
}
