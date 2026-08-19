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
# This script deploys CloudNativePG in one or more regions and sets up
# PostgreSQL clusters using either a standalone configuration (single region)
# or a distributed topology (multiple regions, circular replica chain).
# State synchronization is managed via S3 object storage backed by RustFS.
#
# Usage:
#   ./demo/setup.sh [regions...]        # specify regions (auto-detects running clusters if omitted)
#   LEGACY=true  ./demo/setup.sh        # use in-tree Barman backup instead of plugin
#   TRUNK=true   ./demo/setup.sh        # deploy from main branch (CNPG + Barman plugin)
#   KLIO=true    ./demo/setup.sh        # also protect clusters with Klio, alongside the Barman Cloud Plugin
#   BARMAN_CLOUD_PLUGIN=false KLIO=true ./demo/setup.sh  # protect clusters with Klio alone
#                                                  # (single region only, requires KLIO=true,
#                                                  # incompatible with LEGACY=true)
#   REQUIREMENTS_ONLY=true ./demo/setup.sh  # deploy CNPG + cert-manager + the selected backup plugin(s) only
#   DEBUG=true  ./demo/setup.sh         # enable shell trace output (set -x)
#
# Note: This environment is for learning purposes only and should not be
# used in production.
#

set -eu
[[ "${DEBUG:-false}" == "true" ]] && set -x

# Source the common setup script
# shellcheck source=scripts/common.sh
source "$(cd "$(dirname "$0")/.." && pwd)/scripts/common.sh"

# Source the CNPG operator/cert-manager/Barman Cloud Plugin deployment function
# shellcheck source=demo/funcs_requirements.sh
source "${REPO_ROOT}/demo/funcs_requirements.sh"

# Source the YAML-rendering helper functions (format_duration, get_source_region)
# shellcheck source=demo/funcs_render.sh
source "${REPO_ROOT}/demo/funcs_render.sh"

kube_config_path="${KUBE_CONFIG_PATH}"
templates_dir="${TEMPLATES_DIR:-${REPO_ROOT}/demo/templates}"
barman_cloud_templates_dir="${templates_dir}/barman-cloud"
legacy_templates_dir="${templates_dir}/legacy"

# Default PostgreSQL major version for plugin mode (selects the entry in
# IMAGE_CATALOG_NAME's ClusterImageCatalog). Legacy mode still selects a
# full image name directly, since the catalog only ships minimal images.
POSTGRESQL_VERSION="${POSTGRESQL_VERSION:-18}"
POSTGRESQL_LEGACY_IMAGE="${POSTGRESQL_LEGACY_IMAGE:-ghcr.io/cloudnative-pg/postgresql:18-system-trixie}"

# Template file overrides — set any of these to replace the corresponding built-in fragment
tmpl_cluster="${CLUSTER_TEMPLATE:-${templates_dir}/cluster.yaml}"
tmpl_storage="${STORAGE_TEMPLATE:-${templates_dir}/storage.yaml}"
tmpl_bootstrap_initdb="${BOOTSTRAP_INITDB_TEMPLATE:-${templates_dir}/bootstrap-initdb.yaml}"
tmpl_bootstrap_recovery="${BOOTSTRAP_RECOVERY_TEMPLATE:-${templates_dir}/bootstrap-recovery.yaml}"
tmpl_image_catalog="${IMAGE_CATALOG_TEMPLATE:-${templates_dir}/image-catalog.yaml}"
tmpl_cluster_plugin_params="${CLUSTER_PLUGIN_PARAMS_TEMPLATE:-${barman_cloud_templates_dir}/cluster-params.yaml}"
tmpl_replica_section="${REPLICA_SECTION_TEMPLATE:-${templates_dir}/replica-section.yaml}"
tmpl_external_cluster_plugin="${EXTERNAL_CLUSTER_PLUGIN_TEMPLATE:-${barman_cloud_templates_dir}/external-cluster.yaml}"
tmpl_scheduledbackup_plugin="${SCHEDULEDBACKUP_PLUGIN_TEMPLATE:-${barman_cloud_templates_dir}/scheduledbackup.yaml}"
tmpl_objectstore="${OBJECTSTORE_TEMPLATE:-${barman_cloud_templates_dir}/objectstore.yaml}"
tmpl_podmonitor="${PODMONITOR_TEMPLATE:-${templates_dir}/podmonitor.yaml}"
tmpl_klio_server="${KLIO_SERVER_TEMPLATE:-${templates_dir}/klio/server.yaml}"
tmpl_klio_pluginconfig="${KLIO_PLUGINCONFIG_TEMPLATE:-${templates_dir}/klio/pluginconfiguration.yaml}"
tmpl_klio_cluster_params="${KLIO_CLUSTER_PARAMS_TEMPLATE:-${templates_dir}/klio/cluster-klio-params.yaml}"
tmpl_klio_pg_hba="${KLIO_PG_HBA_TEMPLATE:-${templates_dir}/klio/postgresql-pg-hba.yaml}"
tmpl_scheduledbackup_klio="${SCHEDULEDBACKUP_KLIO_TEMPLATE:-${templates_dir}/klio/scheduledbackup-klio.yaml}"
tmpl_cluster_legacy_params="${CLUSTER_LEGACY_PARAMS_TEMPLATE:-${legacy_templates_dir}/cluster-legacy-params.yaml}"
tmpl_image_legacy="${IMAGE_LEGACY_TEMPLATE:-${legacy_templates_dir}/image-legacy.yaml}"
tmpl_external_cluster_legacy="${EXTERNAL_CLUSTER_LEGACY_TEMPLATE:-${legacy_templates_dir}/external-cluster-legacy.yaml}"
tmpl_scheduledbackup_legacy="${SCHEDULEDBACKUP_LEGACY_TEMPLATE:-${legacy_templates_dir}/scheduledbackup-legacy.yaml}"

legacy=false
if [ "${LEGACY:-}" = "true" ]; then
    legacy=true
fi

klio=false
if [ "${KLIO:-}" = "true" ]; then
    klio=true
fi

if ${klio} && ${legacy}; then
    echo "KLIO=true has no effect together with LEGACY=true (Klio requires plugin mode); ignoring KLIO."
    klio=false
fi

# Only meaningful in plugin mode (LEGACY=false): whether the Barman Cloud
# Plugin protects the cluster. Defaults to true, so BARMAN_CLOUD_PLUGIN=false is only
# useful together with KLIO=true, to run Klio on its own.
barman_cloud_plugin=true
if [ "${BARMAN_CLOUD_PLUGIN:-}" = "false" ]; then
    barman_cloud_plugin=false
fi

if ${legacy} && ! ${barman_cloud_plugin}; then
    echo "BARMAN_CLOUD_PLUGIN=false has no effect together with LEGACY=true (legacy mode doesn't use the Barman Cloud Plugin); ignoring BARMAN_CLOUD_PLUGIN."
    barman_cloud_plugin=true
fi

if ! ${legacy} && ! ${barman_cloud_plugin} && ! ${klio}; then
    echo "BARMAN_CLOUD_PLUGIN=false requires KLIO=true (otherwise no backup plugin would be configured)."
    exit 1
fi

trunk=0
if [ "${TRUNK:-}" = "true" ]; then
    trunk=1
fi

requirements_only=false
if [ "${REQUIREMENTS_ONLY:-}" = "true" ]; then
    requirements_only=true
fi

dry_run=false
if [ "${DRY_RUN:-}" = "true" ]; then
    dry_run=true
fi

output_dir=""
if [ -n "${OUTPUT_DIR:-}" ]; then
    output_dir="${OUTPUT_DIR}"
    mkdir -p "${output_dir}"
fi

# Disable trace only when DRY_RUN prints to stdout (i.e. OUTPUT_DIR is not set),
# so that the YAML output is not polluted by the trace.
if ${dry_run} && [ -z "${output_dir}" ]; then
    set +x
fi

# Ensure prerequisites are met
for cmd in kubectl kubectl-cnpg cmctl envsubst; do
    if ! command -v "${cmd}" &>/dev/null; then
        echo "Missing command ${cmd}"
        exit 1
    fi
done

# Helm is only needed to install the Klio Operator
if ${klio} && ! command -v helm &>/dev/null; then
    echo "Missing command helm (required when KLIO=true)"
    exit 1
fi

# Set regions from arguments, or auto-detect running playground clusters
detect_running_regions "$@"
primary_region="${REGIONS[0]}"
num_regions=${#REGIONS[@]}

# Klio-alone (BARMAN_CLOUD_PLUGIN=false) protects each region's cluster independently; it
# does not implement the cross-region WAL-archive bootstrap that the
# distributed topology relies on (that's provided by the Barman Cloud
# Plugin's externalClusters, when BARMAN_CLOUD_PLUGIN=true).
if ${klio} && ! ${barman_cloud_plugin} && [ "${num_regions}" -gt 1 ]; then
    echo "BARMAN_CLOUD_PLUGIN=false is only supported with a single region; got: ${REGIONS[*]}"
    exit 1
fi

# Consume generated YAML from stdin, then:
#   - append to ${output_dir}/${region}.yaml  if OUTPUT_DIR is set
#   - print to stdout                         if DRY_RUN is true
#   - apply to the cluster                    if DRY_RUN is false
# The options compose: OUTPUT_DIR + DRY_RUN writes the file and prints to stdout.
kubectl_apply() {
    local input
    input=$(cat)

    if [ -n "${output_dir}" ]; then
        # OUTPUT_DIR is set: write to file (DRY_RUN skips kubectl apply)
        printf '%s\n---\n' "${input}" >>"${output_dir}/${region}.yaml"
    elif ${dry_run}; then
        # DRY_RUN without OUTPUT_DIR: print to stdout
        printf '%s\n---\n' "${input}"
    else
        printf '%s\n' "${input}" | kubectl apply --context "${CONTEXT_NAME}" -f -
    fi
}

# ---------------------------------------------------------------------------
# YAML generators — each function writes a complete YAML stream to stdout.
# The caller is responsible for piping to kubectl.
# Template files use ${REGION}, ${PRIMARY_REGION}, ${SOURCE_REGION},
# ${IMAGE_CATALOG_NAME}, ${POSTGRESQL_VERSION}, and ${POSTGRESQL_LEGACY_IMAGE}
# placeholders; envsubst substitutes only those
# variables (explicit list prevents accidental expansion of env vars).
# ---------------------------------------------------------------------------

generate_objectstore_yaml() {
    local region="$1"
    REGION="${region}" \
        envsubst '${REGION}' <"${tmpl_objectstore}"
}

generate_podmonitor_yaml() {
    local region="$1"
    REGION="${region}" \
        envsubst '${REGION}' <"${tmpl_podmonitor}"
}

# Emit the per-region Klio Server + PluginConfiguration stream (KLIO=true).
# Reuses the region's RustFS instance and credentials for tier 2 storage
# (see demo/templates/barman-cloud/objectstore.yaml).
generate_klio_yaml() {
    local region="$1"
    REGION="${region}" KLIO_VERSION="${KLIO_VERSION}" \
        envsubst '${REGION} ${KLIO_VERSION}' <"${tmpl_klio_server}"
    REGION="${region}" \
        envsubst '${REGION}' <"${tmpl_klio_pluginconfig}"
}

# Emit a Cluster + ScheduledBackup stream protected by the Barman Cloud
# Plugin (BARMAN_CLOUD_PLUGIN=true, the default), Klio (KLIO=true), or both at once.
# BARMAN_CLOUD_PLUGIN=false requires KLIO=true and only supports a single region, since
# only the Barman Cloud Plugin provides the cross-region WAL-archive
# bootstrap the distributed topology relies on (see externalClusters below).
generate_cluster_yaml_plugin() {
    local region="$1"
    local source_region
    source_region=$(get_source_region "${region}" "${REGIONS[@]}")

    # Cluster header: apiVersion through affinity
    REGION="${region}" \
        envsubst '${REGION}' <"${tmpl_cluster}"

    # Extra pg_hba rule, appended into the still-open "postgresql:" mapping
    # from the header above. Klio's "send-wal" client needs a local
    # replication connection over the Unix socket, which isn't allowed by
    # PostgreSQL's default pg_hba rules.
    if ${klio}; then
        cat "${tmpl_klio_pg_hba}"
    fi

    # Storage (data + WAL volumes)
    cat "${tmpl_storage}"

    # ClusterImageCatalog reference (see demo/funcs_requirements.sh for the catalog itself)
    IMAGE_CATALOG_NAME="${IMAGE_CATALOG_NAME}" POSTGRESQL_VERSION="${POSTGRESQL_VERSION}" \
        envsubst '${IMAGE_CATALOG_NAME} ${POSTGRESQL_VERSION}' <"${tmpl_image_catalog}"

    # Bootstrap: initdb for the primary (or single-region); recovery for
    # replicas (multi-region only happens with BARMAN_CLOUD_PLUGIN=true, see the
    # BARMAN_CLOUD_PLUGIN=false/num_regions check above)
    if [ "${region}" = "${primary_region}" ] || [ "${num_regions}" -eq 1 ]; then
        cat "${tmpl_bootstrap_initdb}"
    else
        PRIMARY_REGION="${primary_region}" \
            envsubst '${PRIMARY_REGION}' <"${tmpl_bootstrap_recovery}"
    fi

    # Plugin list: Barman Cloud Plugin (BARMAN_CLOUD_PLUGIN=true) and/or Klio (KLIO=true)
    if ${barman_cloud_plugin} || ${klio}; then
        printf '  plugins:\n'
    fi
    if ${barman_cloud_plugin}; then
        REGION="${region}" \
            envsubst '${REGION}' <"${tmpl_cluster_plugin_params}"
    fi
    if ${klio}; then
        REGION="${region}" \
            envsubst '${REGION}' <"${tmpl_klio_cluster_params}"
    fi

    # Distributed topology replica section, only for multi-region setups
    # (BARMAN_CLOUD_PLUGIN=true only, see above)
    if ${barman_cloud_plugin} && [ "${num_regions}" -gt 1 ]; then
        REGION="${region}" PRIMARY_REGION="${primary_region}" SOURCE_REGION="${source_region}" \
            envsubst '${REGION} ${PRIMARY_REGION} ${SOURCE_REGION}' <"${tmpl_replica_section}"
    fi

    if ${barman_cloud_plugin}; then
        # External cluster references, one entry per region
        printf '  externalClusters:\n'
        local r
        for r in "${REGIONS[@]}"; do
            REGION="${r}" envsubst '${REGION}' <"${tmpl_external_cluster_plugin}"
        done

        # Barman Cloud Plugin ScheduledBackup document: always the active
        # backup engine when enabled, whether Klio is attached or not.
        REGION="${region}" \
            envsubst '${REGION}' <"${tmpl_scheduledbackup_plugin}"
    fi

    # Klio's own ScheduledBackup document. When Klio runs alone
    # (BARMAN_CLOUD_PLUGIN=false) this is the active tier2 backup engine.
    # When it runs alongside Barman (both enabled) it is rendered *suspended*
    # instead: a migration-readiness artifact sitting next to Barman's active
    # ScheduledBackup above, which already exercises continuous protection in
    # that case. Completing a migration to Klio means un-suspending this
    # document and retiring Barman's.
    if ${klio}; then
        local klio_scheduledbackup_suspend=false klio_scheduledbackup_immediate=true
        if ${barman_cloud_plugin}; then
            klio_scheduledbackup_suspend=true
            klio_scheduledbackup_immediate=false
        fi
        REGION="${region}" \
            KLIO_SCHEDULEDBACKUP_SUSPEND="${klio_scheduledbackup_suspend}" \
            KLIO_SCHEDULEDBACKUP_IMMEDIATE="${klio_scheduledbackup_immediate}" \
            envsubst '${REGION} ${KLIO_SCHEDULEDBACKUP_SUSPEND} ${KLIO_SCHEDULEDBACKUP_IMMEDIATE}' \
            <"${tmpl_scheduledbackup_klio}"
    fi
}

# Emit a Cluster + ScheduledBackup stream using in-tree (legacy) Barman configuration
generate_cluster_yaml_legacy() {
    local region="$1"
    local source_region
    source_region=$(get_source_region "${region}" "${REGIONS[@]}")

    REGION="${region}" \
        envsubst '${REGION}' <"${tmpl_cluster}"

    # Storage (data + WAL volumes)
    cat "${tmpl_storage}"

    # Direct image reference — no catalog available for legacy/system images
    POSTGRESQL_LEGACY_IMAGE="${POSTGRESQL_LEGACY_IMAGE}" \
        envsubst '${POSTGRESQL_LEGACY_IMAGE}' <"${tmpl_image_legacy}"

    if [ "${region}" = "${primary_region}" ] || [ "${num_regions}" -eq 1 ]; then
        cat "${tmpl_bootstrap_initdb}"
    else
        PRIMARY_REGION="${primary_region}" \
            envsubst '${PRIMARY_REGION}' <"${tmpl_bootstrap_recovery}"
    fi

    REGION="${region}" \
        envsubst '${REGION}' <"${tmpl_cluster_legacy_params}"

    if [ "${num_regions}" -gt 1 ]; then
        REGION="${region}" PRIMARY_REGION="${primary_region}" SOURCE_REGION="${source_region}" \
            envsubst '${REGION} ${PRIMARY_REGION} ${SOURCE_REGION}' <"${tmpl_replica_section}"
    fi

    printf '  externalClusters:\n'
    local r
    for r in "${REGIONS[@]}"; do
        REGION="${r}" envsubst '${REGION}' <"${tmpl_external_cluster_legacy}"
    done

    REGION="${region}" \
        envsubst '${REGION}' <"${tmpl_scheduledbackup_legacy}"
}

# ---------------------------------------------------------------------------
# Deployment
# ---------------------------------------------------------------------------

cd "${REPO_ROOT}"
export KUBECONFIG="${kube_config_path}"

total_start=$SECONDS

for region in "${REGIONS[@]}"; do

    CONTEXT_NAME=$(get_cluster_context "${region}")
    region_start=$SECONDS

    # Initialise the per-region output file (clears any previous run)
    if [ -n "${output_dir}" ]; then
        : >"${output_dir}/${region}.yaml"
    fi

    if ! ${dry_run}; then
        deploy_cnpg_requirements "${region}" "${CONTEXT_NAME}"
        if ${klio}; then
            deploy_klio_requirements "${region}" "${CONTEXT_NAME}"
        fi
    fi

    # REQUIREMENTS_ONLY stops here, before any cluster-specific resources are generated
    if ${requirements_only}; then
        if ! ${dry_run}; then
            echo "✅ Requirements deployment for '${region}' complete in $(format_duration $((SECONDS - region_start)))."
        fi
        continue
    fi

    # Create the Barman ObjectStore CRs for all regions (plugin mode with
    # BARMAN_CLOUD_PLUGIN=true, i.e. LEGACY=false and BARMAN_CLOUD_PLUGIN=true)
    # Each cluster needs ObjectStores for all regions to support externalClusters references.
    if ! ${legacy} && ${barman_cloud_plugin}; then
        for r in "${REGIONS[@]}"; do
            generate_objectstore_yaml "${r}" | kubectl_apply
        done
    fi

    # Create the Klio Server and PluginConfiguration for this region, ahead
    # of the Cluster that references them (KLIO=true)
    if ${klio}; then
        generate_klio_yaml "${region}" | kubectl_apply
    fi

    # Create the Postgres cluster (plugin or legacy mode)
    if ${legacy}; then
        generate_cluster_yaml_legacy "${region}"
    else
        generate_cluster_yaml_plugin "${region}"
    fi | kubectl_apply

    # Create the PodMonitor if Prometheus has been installed
    # In dry-run mode always emit it; otherwise check for the CRD first
    if ${dry_run} || check_crd_existence "${CONTEXT_NAME}" podmonitors.monitoring.coreos.com; then
        generate_podmonitor_yaml "${region}" | kubectl_apply
    fi

    if ! ${dry_run}; then
        # Wait for the cluster to be ready
        kubectl wait --context "${CONTEXT_NAME}" \
            --timeout 30m \
            --for=condition=Ready cluster/pg-${region}

        echo "✅ Demo deployment for '${region}' complete in $(format_duration $((SECONDS - region_start)))."
    fi

done

if ! ${dry_run}; then
    echo
    echo "⏱️  Total demo setup time: $(format_duration $((SECONDS - total_start)))."
fi
