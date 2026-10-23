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
# Regenerates tests/dryrun/golden/* from the current demo/setup.sh + templates.
# Run this after an intentional rendering change, then review the diff:
#
#   ./tests/dryrun/update-golden.sh
#   git diff tests/dryrun/golden/
#

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
golden_dir="${repo_root}/tests/dryrun/golden"

PATH="${repo_root}/tests/helpers/stubs:${PATH}"
export PATH
KUBECONFIG="$(mktemp -u)"
export KUBECONFIG

rm -rf "${golden_dir}"
mkdir -p "${golden_dir}"/{plugin-eu,plugin-eu-na,legacy-eu,legacy-eu-na}

DRY_RUN=true OUTPUT_DIR="${golden_dir}/plugin-eu" "${repo_root}/demo/setup.sh" eu
DRY_RUN=true OUTPUT_DIR="${golden_dir}/plugin-eu-na" "${repo_root}/demo/setup.sh" eu na
LEGACY=true DRY_RUN=true OUTPUT_DIR="${golden_dir}/legacy-eu" "${repo_root}/demo/setup.sh" eu
LEGACY=true DRY_RUN=true OUTPUT_DIR="${golden_dir}/legacy-eu-na" "${repo_root}/demo/setup.sh" eu na

echo "✅ Golden fixtures regenerated under ${golden_dir}"
