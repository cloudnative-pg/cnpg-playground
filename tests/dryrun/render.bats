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
# Drives demo/setup.sh with DRY_RUN=true OUTPUT_DIR=... across the
# plugin/legacy x single/multi-region matrix and checks the rendered YAML
# against committed fixtures in tests/dryrun/golden/. demo/setup.sh checks
# for kind/kubectl/kubectl-cnpg/cmctl on PATH but never actually invokes them
# in DRY_RUN mode, so tests/helpers/stubs stands in for the real tools.
#

setup() {
    repo_root="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    golden_dir="${repo_root}/tests/dryrun/golden"
    PATH="${repo_root}/tests/helpers/stubs:${PATH}"
    export PATH
    export KUBECONFIG="${BATS_TEST_TMPDIR}/kubeconfig.yaml"
}

# Fails if any rendered file is not well-formed YAML, or still contains a
# literal `${` (a missed or typo'd envsubst variable).
assert_rendered_yaml_is_clean() {
    local dir="$1"
    local f
    for f in "${dir}"/*.yaml; do
        yq eval-all '.' "${f}" >/dev/null
        run grep -F '${' "${f}"
        [ "${status}" -ne 0 ]
    done
}

@test "plugin mode, single region (eu): renders and matches golden fixture" {
    DRY_RUN=true OUTPUT_DIR="${BATS_TEST_TMPDIR}/out" run "${repo_root}/demo/setup.sh" eu
    [ "${status}" -eq 0 ]
    assert_rendered_yaml_is_clean "${BATS_TEST_TMPDIR}/out"
    diff -r "${golden_dir}/plugin-eu" "${BATS_TEST_TMPDIR}/out"
}

@test "plugin mode, two regions (eu na): renders and matches golden fixture" {
    DRY_RUN=true OUTPUT_DIR="${BATS_TEST_TMPDIR}/out" run "${repo_root}/demo/setup.sh" eu na
    [ "${status}" -eq 0 ]
    assert_rendered_yaml_is_clean "${BATS_TEST_TMPDIR}/out"
    diff -r "${golden_dir}/plugin-eu-na" "${BATS_TEST_TMPDIR}/out"
}

@test "legacy mode, single region (eu): renders and matches golden fixture" {
    LEGACY=true DRY_RUN=true OUTPUT_DIR="${BATS_TEST_TMPDIR}/out" run "${repo_root}/demo/setup.sh" eu
    [ "${status}" -eq 0 ]
    assert_rendered_yaml_is_clean "${BATS_TEST_TMPDIR}/out"
    diff -r "${golden_dir}/legacy-eu" "${BATS_TEST_TMPDIR}/out"
}

@test "legacy mode, two regions (eu na): renders and matches golden fixture" {
    LEGACY=true DRY_RUN=true OUTPUT_DIR="${BATS_TEST_TMPDIR}/out" run "${repo_root}/demo/setup.sh" eu na
    [ "${status}" -eq 0 ]
    assert_rendered_yaml_is_clean "${BATS_TEST_TMPDIR}/out"
    diff -r "${golden_dir}/legacy-eu-na" "${BATS_TEST_TMPDIR}/out"
}

@test "REQUIREMENTS_ONLY stops before any YAML generation" {
    REQUIREMENTS_ONLY=true DRY_RUN=true OUTPUT_DIR="${BATS_TEST_TMPDIR}/out" run "${repo_root}/demo/setup.sh" eu
    [ "${status}" -eq 0 ]
    [ -f "${BATS_TEST_TMPDIR}/out/eu.yaml" ]
    [ ! -s "${BATS_TEST_TMPDIR}/out/eu.yaml" ]
}
