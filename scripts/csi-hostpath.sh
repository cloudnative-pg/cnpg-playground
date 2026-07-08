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
# Deploys the CSI hostpath driver with volume snapshot support to the current
# kubectl context, using the distributed (per-node) deployment so that each
# PostgreSQL instance gets node-local storage and per-node snapshot support.
#
# To keep maintenance low, the upstream kubernetes-csi manifests are applied
# straight from their pinned versions (see common.sh) and only small local deltas
# are layered on top:
#
#   - k8s/csi-hostpath/csi-hostpath-plugin-patch.yaml   adds a csi-snapshotter
#       sidecar (distributed snapshotting) + the postgres taint toleration to the
#       upstream node-plugin DaemonSet
#   - k8s/csi-hostpath/snapshot-controller-patch.yaml   enables distributed
#       snapshotting on the upstream snapshot-controller
#   - k8s/csi-hostpath/csi-hostpath-rbac.yaml           binds external-snapshotter-runner
#       to the shared csi-provisioner ServiceAccount
#   - k8s/csi-hostpath/csi-hostpath-snapshotclass.yaml  default VolumeSnapshotClass
#       (upstream's distributed deployment ships none)
#
# The upstream distributed deployment runs a DaemonSet on every eligible node and
# provisions volumes locally (--node-deployment=true) with a WaitForFirstConsumer
# StorageClass, so PostgreSQL keeps its required pod anti-affinity spread while
# each instance gets node-local storage.
#

# --- Deploy the CSI hostpath driver + snapshot support ---
# Expects the caller to have selected the target cluster context. REPO_ROOT and
# the version variables come from common.sh.
deploy_csi_host_path() {
    local csi_base="https://raw.githubusercontent.com/kubernetes-csi/csi-driver-host-path/${CSI_DRIVER_HOST_PATH_VERSION}"
    local snap_base="https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/${EXTERNAL_SNAPSHOTTER_VERSION}"
    local prov_base="https://raw.githubusercontent.com/kubernetes-csi/external-provisioner/${EXTERNAL_PROVISIONER_VERSION}"
    local dist_base="${csi_base}/deploy/kubernetes-distributed/hostpath"
    local manifests_dir="${REPO_ROOT}/k8s/csi-hostpath"

    echo "🗄️  Deploying CSI hostpath driver with volume snapshot support..."

    # 1. Volume snapshot CRDs (cluster-scoped) — must exist before our snapshotclass.
    echo "   - Installing volume snapshot CRDs (external-snapshotter ${EXTERNAL_SNAPSHOTTER_VERSION})"
    kubectl apply -f "${snap_base}/client/config/crd/snapshot.storage.k8s.io_volumesnapshotclasses.yaml"
    kubectl apply -f "${snap_base}/client/config/crd/snapshot.storage.k8s.io_volumesnapshotcontents.yaml"
    kubectl apply -f "${snap_base}/client/config/crd/snapshot.storage.k8s.io_volumesnapshots.yaml"

    # 2. Upstream RBAC: creates the csi-provisioner ServiceAccount and the
    #    external-provisioner-runner / external-snapshotter-runner ClusterRoles.
    #    Upstream hardcodes `namespace: default` for the ServiceAccounts and their
    #    namespaced Roles/bindings; relocate those to kube-system (client-side
    #    rewrite, no extra tooling — kubectl fetches the URL, sed moves the ns).
    echo "   - Installing upstream provisioner and snapshotter RBAC (in kube-system)"
    kubectl create --dry-run=client -o yaml \
        -f "${prov_base}/deploy/kubernetes/rbac.yaml" \
        | sed "s|namespace: default|namespace: kube-system|g" | kubectl apply -f -
    kubectl create --dry-run=client -o yaml \
        -f "${snap_base}/deploy/kubernetes/csi-snapshotter/rbac-csi-snapshotter.yaml" \
        | sed "s|namespace: default|namespace: kube-system|g" | kubectl apply -f -
    kubectl apply -f "${snap_base}/deploy/kubernetes/snapshot-controller/rbac-snapshot-controller.yaml"

    # 3. Upstream snapshot-controller, patched to enable distributed snapshotting.
    echo "   - Deploying the snapshot controller (distributed snapshotting)"
    kubectl apply -f "${snap_base}/deploy/kubernetes/snapshot-controller/setup-snapshot-controller.yaml"
    kubectl patch deployment snapshot-controller -n kube-system --type=strategic \
        --patch "$(cat "${manifests_dir}/snapshot-controller-patch.yaml")"

    # 4. Upstream distributed driver: CSIDriver + StorageClass, then the node-plugin
    #    DaemonSet patched to add the snapshotter sidecar and the postgres toleration.
    echo "   - Deploying the driver, StorageClass and node plugin (csi-driver-host-path ${CSI_DRIVER_HOST_PATH_VERSION})"
    kubectl apply -f "${dist_base}/csi-hostpath-driverinfo.yaml"
    kubectl apply -f "${dist_base}/csi-hostpath-storageclass-fast.yaml"
    # The upstream DaemonSet declares no namespace; place it in kube-system.
    kubectl apply -n kube-system -f "${dist_base}/csi-hostpath-plugin.yaml"
    kubectl patch daemonset csi-hostpathplugin -n kube-system --type=strategic \
        --patch "$(sed \
            -e "s|\${CSI_SNAPSHOTTER_IMAGE}|${CSI_SNAPSHOTTER_IMAGE}|g" \
            -e "s|\${CSI_DRIVER_HOST_PATH_VERSION}|${CSI_DRIVER_HOST_PATH_VERSION}|g" \
            "${manifests_dir}/csi-hostpath-plugin-patch.yaml")"

    # 5. Our genuinely-local deltas: RBAC binding + default VolumeSnapshotClass.
    echo "   - Binding snapshotter RBAC and installing the VolumeSnapshotClass"
    kubectl apply -f "${manifests_dir}/csi-hostpath-rbac.yaml"
    kubectl apply -f "${manifests_dir}/csi-hostpath-snapshotclass.yaml"

    # 6. Wait for the node plugin and controller to become ready.
    echo "   ⏳ Waiting for the CSI hostpath plugin to be ready..."
    kubectl rollout status daemonset/csi-hostpathplugin -n kube-system --timeout=300s
    kubectl rollout status deployment/snapshot-controller -n kube-system --timeout=300s

    echo "✅ CSI hostpath driver ready (StorageClass '${CSI_STORAGE_CLASS}')."
}
