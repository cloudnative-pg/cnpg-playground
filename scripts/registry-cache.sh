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
# Optional pull-through registry cache for the Kind nodes.
#
# Kind nodes are containers with their own containerd, so images they pull
# never reach the host's image store and are lost with the cluster. This file
# provides helpers to run one pull-through registry container per upstream
# registry (the distribution registry can only proxy a single remote each),
# backed by named volumes that survive `scripts/teardown.sh`, and to point
# every node's containerd at them through `hosts.toml` mirrors. The `server`
# entry keeps the upstream as a fallback if a cache is unreachable.
#
# Functions (sourced by setup.sh and teardown.sh; see REGISTRY_CACHE* in common.sh):
#   start_registry_cache()                    create/start the cache containers
#   configure_registry_cache_nodes <cluster>  attach caches to the Kind network
#                                             and configure the cluster's nodes
#   remove_registry_cache()                   delete the containers and volumes
#

# upstream host (as used in image references) -> remote URL the cache proxies
declare -A REGISTRY_CACHE_REMOTES=(
    ["docker.io"]="https://registry-1.docker.io"
    ["ghcr.io"]="https://ghcr.io"
    ["quay.io"]="https://quay.io"
    ["registry.k8s.io"]="https://registry.k8s.io"
)

# Name shared by the cache container and its volume, e.g. kind-registry-cache-ghcr-io
registry_cache_name() {
    echo "${REGISTRY_CACHE_BASE_NAME}-${1//./-}"
}

start_registry_cache() {
    local host name
    echo "🗄️  Starting pull-through registry caches..."
    for host in "${!REGISTRY_CACHE_REMOTES[@]}"; do
        name=$(registry_cache_name "${host}")
        if [ "$($CONTAINER_PROVIDER inspect -f '{{.State.Running}}' "${name}" 2>/dev/null || true)" == "true" ]; then
            echo "   🔷 '${name}' already running."
            continue
        fi
        if $CONTAINER_PROVIDER inspect "${name}" >/dev/null 2>&1; then
            echo "   ▶️  Starting existing '${name}'..."
            $CONTAINER_PROVIDER start "${name}" >/dev/null
            continue
        fi
        echo "   📦 Creating '${name}' (proxy for ${host})..."
        $CONTAINER_PROVIDER volume create "${name}" >/dev/null
        $CONTAINER_PROVIDER run -d --name "${name}" \
            --restart unless-stopped \
            -v "${name}:/var/lib/registry" \
            -e "REGISTRY_PROXY_REMOTEURL=${REGISTRY_CACHE_REMOTES[${host}]}" \
            "${REGISTRY_CACHE_IMAGE}" >/dev/null
    done
}

# Must run after `kind create cluster`, which creates the `kind` network.
configure_registry_cache_nodes() {
    local cluster="$1" host name node remote
    echo "🗄️  Attaching registry caches to the Kind network..."
    for host in "${!REGISTRY_CACHE_REMOTES[@]}"; do
        name=$(registry_cache_name "${host}")
        # Idempotent: ignore "already connected" on later clusters
        $CONTAINER_PROVIDER network connect kind "${name}" 2>/dev/null || true
    done

    echo "🗄️  Configuring containerd mirrors on the nodes of '${cluster}'..."
    # Kind's node image already enables /etc/containerd/certs.d, and containerd
    # reads hosts.toml on every pull, so no restart is needed.
    for node in $(kind get nodes --name "${cluster}"); do
        for host in "${!REGISTRY_CACHE_REMOTES[@]}"; do
            name=$(registry_cache_name "${host}")
            remote="${REGISTRY_CACHE_REMOTES[${host}]}"
            $CONTAINER_PROVIDER exec -i "${node}" sh -c \
                "mkdir -p /etc/containerd/certs.d/${host} && cat > /etc/containerd/certs.d/${host}/hosts.toml" <<EOT
server = "${remote}"

[host."http://${name}:5000"]
  capabilities = ["pull", "resolve"]
EOT
        done
    done
}

remove_registry_cache() {
    local host name
    for host in "${!REGISTRY_CACHE_REMOTES[@]}"; do
        name=$(registry_cache_name "${host}")
        if $CONTAINER_PROVIDER inspect "${name}" >/dev/null 2>&1; then
            echo "🗑️  Removing registry cache '${name}'..."
            $CONTAINER_PROVIDER rm -f "${name}" >/dev/null
        fi
        if $CONTAINER_PROVIDER volume inspect "${name}" >/dev/null 2>&1; then
            echo "🗑️  Removing registry cache volume '${name}'..."
            $CONTAINER_PROVIDER volume rm "${name}" >/dev/null
        fi
    done
}
