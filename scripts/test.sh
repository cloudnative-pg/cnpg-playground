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
# Local test runner: shellcheck, shfmt -d, then the bats suite. See
# tests/README.md for required tools and how to run individual tiers.
#

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "${repo_root}" || exit 1

shell_scripts=(scripts/*.sh demo/*.sh monitoring/*.sh)

echo "🔎 Running shellcheck..."
shellcheck -x --severity=warning "${shell_scripts[@]}"
echo "✅ shellcheck passed."
echo

echo "🔎 Running shfmt..."
shfmt -i 4 -ci -d "${shell_scripts[@]}"
echo "✅ shfmt passed."
echo

echo "🔎 Running bats test suite..."
bats -r tests/
echo "✅ bats passed."
echo

echo "🎉 All checks passed."
