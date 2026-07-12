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
#   LEGACY=true ./demo/setup.sh         # use in-tree Barman backup instead of plugin
#   TRUNK=true  ./demo/setup.sh         # deploy from main branch (CNPG + Barman plugin)
#   REQUIREMENTS_ONLY=true ./demo/setup.sh  # deploy CNPG + cert-manager + Barman plugin only
#   DEBUG=true  ./demo/setup.sh         # enable shell trace output (set -x)
#
# Note: This environment is for learning purposes only and should not be
# used in production.
#

set -eu
[[ "${DEBUG:-false}" == "true" ]] && set -x

# Source the common setup script
source "$(cd "$(dirname "$0")/.." && pwd)/scripts/common.sh"

# Source the CNPG operator/cert-manager/Barman Cloud Plugin deployment function
source "${REPO_ROOT}/demo/funcs_requirements.sh"

kube_config_path="${KUBE_CONFIG_PATH}"
templates_dir="${TEMPLATES_DIR:-${REPO_ROOT}/demo/templates}"
legacy_templates_dir="${templates_dir}/legacy"

# Default PostgreSQL major version for plugin mode (selects the entry in
# IMAGE_CATALOG_NAME's ClusterImageCatalog). Legacy mode still selects a
# full image name directly, since the catalog only ships minimal images.
POSTGRESQL_VERSION="${POSTGRESQL_VERSION:-18}"
POSTGRESQL_LEGACY_IMAGE="${POSTGRESQL_LEGACY_IMAGE:-ghcr.io/cloudnative-pg/postgresql:18-system-trixie}"

# StorageClass for the PostgreSQL clusters. Defaults to the CSI hostpath class
# deployed by scripts/setup.sh (node-local storage with volume snapshot support).
# Set STORAGE_CLASS="" to use each cluster's default StorageClass instead.
STORAGE_CLASS="${STORAGE_CLASS-${CSI_STORAGE_CLASS:-csi-hostpath-fast}}"

# VolumeSnapshotClass for snapshot-based backups. Only meaningful when the
# clusters use the CSI hostpath StorageClass (the class shipped with the driver);
# with any other/default StorageClass there is no snapshot-capable storage, so the
# backup.volumeSnapshot block is omitted. Set VOLUME_SNAPSHOT_CLASS="" to disable,
# or to a custom VolumeSnapshotClass name.
if [ -n "${STORAGE_CLASS}" ] && [ "${STORAGE_CLASS}" = "${CSI_STORAGE_CLASS:-csi-hostpath-fast}" ]; then
    VOLUME_SNAPSHOT_CLASS="${VOLUME_SNAPSHOT_CLASS-csi-hostpath-snapclass}"
else
    VOLUME_SNAPSHOT_CLASS="${VOLUME_SNAPSHOT_CLASS-}"
fi

# Template file overrides — set any of these to replace the corresponding built-in fragment
tmpl_cluster="${CLUSTER_TEMPLATE:-${templates_dir}/cluster.yaml}"
tmpl_bootstrap_initdb="${BOOTSTRAP_INITDB_TEMPLATE:-${templates_dir}/bootstrap-initdb.yaml}"
tmpl_bootstrap_recovery="${BOOTSTRAP_RECOVERY_TEMPLATE:-${templates_dir}/bootstrap-recovery.yaml}"
tmpl_image_catalog="${IMAGE_CATALOG_TEMPLATE:-${templates_dir}/image-catalog.yaml}"
tmpl_cluster_plugin_params="${CLUSTER_PLUGIN_PARAMS_TEMPLATE:-${templates_dir}/cluster-plugin-params.yaml}"
tmpl_replica_section="${REPLICA_SECTION_TEMPLATE:-${templates_dir}/replica-section.yaml}"
tmpl_external_cluster_plugin="${EXTERNAL_CLUSTER_PLUGIN_TEMPLATE:-${templates_dir}/external-cluster-plugin.yaml}"
tmpl_scheduledbackup_plugin="${SCHEDULEDBACKUP_PLUGIN_TEMPLATE:-${templates_dir}/scheduledbackup-plugin.yaml}"
tmpl_backup_volumesnapshot="${BACKUP_VOLUMESNAPSHOT_TEMPLATE:-${templates_dir}/backup-volumesnapshot.yaml}"
tmpl_objectstore="${OBJECTSTORE_TEMPLATE:-${templates_dir}/objectstore.yaml}"
tmpl_podmonitor="${PODMONITOR_TEMPLATE:-${templates_dir}/podmonitor.yaml}"
tmpl_cluster_legacy_params="${CLUSTER_LEGACY_PARAMS_TEMPLATE:-${legacy_templates_dir}/cluster-legacy-params.yaml}"
tmpl_image_legacy="${IMAGE_LEGACY_TEMPLATE:-${legacy_templates_dir}/image-legacy.yaml}"
tmpl_external_cluster_legacy="${EXTERNAL_CLUSTER_LEGACY_TEMPLATE:-${legacy_templates_dir}/external-cluster-legacy.yaml}"
tmpl_scheduledbackup_legacy="${SCHEDULEDBACKUP_LEGACY_TEMPLATE:-${legacy_templates_dir}/scheduledbackup-legacy.yaml}"

legacy=false
if [ "${LEGACY:-}" = "true" ]; then
    legacy=true
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

# Set regions from arguments, or auto-detect running playground clusters
detect_running_regions "$@"
primary_region="${REGIONS[0]}"
num_regions=${#REGIONS[@]}

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
    local prev="${REGIONS[$((num_regions - 1))]}"
    local r
    for r in "${REGIONS[@]}"; do
        if [ "${r}" = "${target}" ]; then
            echo "${prev}"
            return
        fi
        prev="${r}"
    done
}

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
        printf '%s\n---\n' "${input}" >> "${output_dir}/${region}.yaml"
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
# ${STORAGE_CLASS}, and ${VOLUME_SNAPSHOT_CLASS},
# ${IMAGE_CATALOG_NAME}, ${POSTGRESQL_VERSION}, and ${POSTGRESQL_LEGACY_IMAGE}
# placeholders; envsubst substitutes only those
# variables (explicit list prevents accidental expansion of env vars).
# ---------------------------------------------------------------------------

generate_objectstore_yaml() {
    local region="$1"
    REGION="${region}" \
    envsubst '${REGION}' < "${tmpl_objectstore}"
}

generate_podmonitor_yaml() {
    local region="$1"
    REGION="${region}" \
    envsubst '${REGION}' < "${tmpl_podmonitor}"
}

# Emit a Cluster + ScheduledBackup stream using the Barman Cloud Plugin
generate_cluster_yaml_plugin() {
    local region="$1"
    local source_region
    source_region=$(get_source_region "${region}")

    # Cluster header: apiVersion through affinity
    REGION="${region}" STORAGE_CLASS="${STORAGE_CLASS}" \
    envsubst '${REGION} ${STORAGE_CLASS}' < "${tmpl_cluster}"

    # ClusterImageCatalog reference (see demo/funcs_requirements.sh for the catalog itself)
    IMAGE_CATALOG_NAME="${IMAGE_CATALOG_NAME}" POSTGRESQL_VERSION="${POSTGRESQL_VERSION}" \
    envsubst '${IMAGE_CATALOG_NAME} ${POSTGRESQL_VERSION}' < "${tmpl_image_catalog}"

    # Bootstrap: initdb for the primary (or single-region); recovery for replicas
    if [ "${region}" = "${primary_region}" ] || [ "${num_regions}" -eq 1 ]; then
        cat "${tmpl_bootstrap_initdb}"
    else
        PRIMARY_REGION="${primary_region}" \
        envsubst '${PRIMARY_REGION}' < "${tmpl_bootstrap_recovery}"
    fi

    # PostgreSQL parameters and Barman Cloud Plugin configuration
    REGION="${region}" \
    envsubst '${REGION}' < "${tmpl_cluster_plugin_params}"

    # Volume snapshot backup config (only when using snapshot-capable storage).
    # Plugin mode has no spec.backup otherwise, so open it here.
    if [ -n "${VOLUME_SNAPSHOT_CLASS}" ]; then
        printf '  backup:\n'
        VOLUME_SNAPSHOT_CLASS="${VOLUME_SNAPSHOT_CLASS}" \
        envsubst '${VOLUME_SNAPSHOT_CLASS}' < "${tmpl_backup_volumesnapshot}"
    fi

    # Distributed topology replica section — only for multi-region setups
    if [ "${num_regions}" -gt 1 ]; then
        REGION="${region}" PRIMARY_REGION="${primary_region}" SOURCE_REGION="${source_region}" \
        envsubst '${REGION} ${PRIMARY_REGION} ${SOURCE_REGION}' < "${tmpl_replica_section}"
    fi

    # External cluster references — one entry per region
    printf '  externalClusters:\n'
    local r
    for r in "${REGIONS[@]}"; do
        REGION="${r}" envsubst '${REGION}' < "${tmpl_external_cluster_plugin}"
    done

    # ScheduledBackup document
    REGION="${region}" \
    envsubst '${REGION}' < "${tmpl_scheduledbackup_plugin}"
}

# Emit a Cluster + ScheduledBackup stream using in-tree (legacy) Barman configuration
generate_cluster_yaml_legacy() {
    local region="$1"
    local source_region
    source_region=$(get_source_region "${region}")

    REGION="${region}" STORAGE_CLASS="${STORAGE_CLASS}" \
    envsubst '${REGION} ${STORAGE_CLASS}' < "${tmpl_cluster}"

    # Direct image reference — no catalog available for legacy/system images
    POSTGRESQL_LEGACY_IMAGE="${POSTGRESQL_LEGACY_IMAGE}" \
    envsubst '${POSTGRESQL_LEGACY_IMAGE}' < "${tmpl_image_legacy}"

    if [ "${region}" = "${primary_region}" ] || [ "${num_regions}" -eq 1 ]; then
        cat "${tmpl_bootstrap_initdb}"
    else
        PRIMARY_REGION="${primary_region}" \
        envsubst '${PRIMARY_REGION}' < "${tmpl_bootstrap_recovery}"
    fi

    REGION="${region}" \
    envsubst '${REGION}' < "${tmpl_cluster_legacy_params}"

    # Volume snapshot backup config (only when using snapshot-capable storage).
    # Legacy mode already opened spec.backup above, so this appends volumeSnapshot
    # as a sibling of barmanObjectStore — it MUST stay adjacent to the params above.
    if [ -n "${VOLUME_SNAPSHOT_CLASS}" ]; then
        VOLUME_SNAPSHOT_CLASS="${VOLUME_SNAPSHOT_CLASS}" \
        envsubst '${VOLUME_SNAPSHOT_CLASS}' < "${tmpl_backup_volumesnapshot}"
    fi

    if [ "${num_regions}" -gt 1 ]; then
        REGION="${region}" PRIMARY_REGION="${primary_region}" SOURCE_REGION="${source_region}" \
        envsubst '${REGION} ${PRIMARY_REGION} ${SOURCE_REGION}' < "${tmpl_replica_section}"
    fi

    printf '  externalClusters:\n'
    local r
    for r in "${REGIONS[@]}"; do
        REGION="${r}" envsubst '${REGION}' < "${tmpl_external_cluster_legacy}"
    done

    REGION="${region}" \
    envsubst '${REGION}' < "${tmpl_scheduledbackup_legacy}"
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
        : > "${output_dir}/${region}.yaml"
    fi

    if ! ${dry_run}; then
        deploy_cnpg_requirements "${region}" "${CONTEXT_NAME}"
    fi

    # REQUIREMENTS_ONLY stops here, before any cluster-specific resources are generated
    if ${requirements_only}; then
        if ! ${dry_run}; then
            echo "✅ Requirements deployment for '${region}' complete in $(format_duration $((SECONDS - region_start)))."
        fi
        continue
    fi

    # Create the Barman ObjectStore CRs for all regions (plugin mode only)
    # Each cluster needs ObjectStores for all regions to support externalClusters references.
    if ! ${legacy}; then
        for r in "${REGIONS[@]}"; do
            generate_objectstore_yaml "${r}" | kubectl_apply
        done
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
