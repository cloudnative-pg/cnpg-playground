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
# kubectl context.
#
# The hostpath driver only works when everything runs on a single node
# (kubernetes-csi/csi-driver-host-path#651). We therefore use the upstream
# *single-node* deployment — which ships the provisioner, attacher, resizer and
# snapshotter sidecars out of the box, so snapshots and restores work — and apply
# it verbatim from its pinned upstream versions (see common.sh). There are NO
# local manifests: the single-replica StatefulSet lands on one untainted worker
# node and every volume and snapshot lives there, so backup and restore always
# co-locate (a SAN-like single shared-storage backend).
#
# The driver is deployed as an available capability. The demo PostgreSQL clusters
# do NOT use it (they keep the cluster's default StorageClass). To exploit it,
# deploy your own cluster with `storageClass: csi-hostpath-sc`, scheduled onto the
# node running the plugin — find it with:
#   kubectl get pods -n default -l app.kubernetes.io/name=csi-hostpathplugin -o wide
# For example, after `REQUIREMENTS_ONLY=true ./demo/setup.sh`.
#

# --- Deploy the CSI hostpath driver + snapshot support ---
# Expects the caller to have selected the target cluster context. The version
# variables come from common.sh.
deploy_csi_host_path() {
    local csi_base="https://raw.githubusercontent.com/kubernetes-csi/csi-driver-host-path/${CSI_DRIVER_HOST_PATH_VERSION}"
    local snap_base="https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/${EXTERNAL_SNAPSHOTTER_VERSION}"
    local prov_base="https://raw.githubusercontent.com/kubernetes-csi/external-provisioner/${EXTERNAL_PROVISIONER_VERSION}"
    local attacher_base="https://raw.githubusercontent.com/kubernetes-csi/external-attacher/${EXTERNAL_ATTACHER_VERSION}"
    local resizer_base="https://raw.githubusercontent.com/kubernetes-csi/external-resizer/${EXTERNAL_RESIZER_VERSION}"
    local health_monitor_base="https://raw.githubusercontent.com/kubernetes-csi/external-health-monitor/${EXTERNAL_HEALTH_MONITOR_VERSION}"
    local hostpath_dir="${csi_base}/deploy/kubernetes-1.34/hostpath"

    echo "🗄️  Deploying CSI hostpath driver with volume snapshot support (single node)..."

    # 1. Volume snapshot CRDs.
    echo "   - Installing volume snapshot CRDs (external-snapshotter ${EXTERNAL_SNAPSHOTTER_VERSION})"
    kubectl apply -f "${snap_base}/client/config/crd/snapshot.storage.k8s.io_volumesnapshotclasses.yaml"
    kubectl apply -f "${snap_base}/client/config/crd/snapshot.storage.k8s.io_volumesnapshotcontents.yaml"
    kubectl apply -f "${snap_base}/client/config/crd/snapshot.storage.k8s.io_volumesnapshots.yaml"

    # 2. Snapshot controller.
    echo "   - Deploying the snapshot controller"
    kubectl apply -f "${snap_base}/deploy/kubernetes/snapshot-controller/rbac-snapshot-controller.yaml"
    kubectl apply -f "${snap_base}/deploy/kubernetes/snapshot-controller/setup-snapshot-controller.yaml"

    # 3. Sidecar RBAC — provides the external-*-runner ClusterRoles the plugin's
    #    ServiceAccount is bound to. Matches upstream's own deploy-hostpath.sh
    #    default RBAC set (provisioner, attacher, snapshotter, resizer,
    #    health-monitor); without the last one, the plugin's
    #    csi-external-health-monitor-controller sidecar runs but every one of its
    #    API calls is denied.
    echo "   - Installing provisioner/attacher/resizer/snapshotter/health-monitor RBAC"
    kubectl apply -f "${prov_base}/deploy/kubernetes/rbac.yaml"
    kubectl apply -f "${attacher_base}/deploy/kubernetes/rbac.yaml"
    kubectl apply -f "${resizer_base}/deploy/kubernetes/rbac.yaml"
    kubectl apply -f "${snap_base}/deploy/kubernetes/csi-snapshotter/rbac-csi-snapshotter.yaml"
    kubectl apply -f "${health_monitor_base}/deploy/kubernetes/external-health-monitor-controller/rbac.yaml"

    # 4. Driver: CSIDriver + the single-node plugin (SA + bindings + StatefulSet).
    echo "   - Deploying the driver and node plugin (csi-driver-host-path ${CSI_DRIVER_HOST_PATH_VERSION})"
    kubectl apply -f "${hostpath_dir}/csi-hostpath-driverinfo.yaml"
    kubectl apply -f "${hostpath_dir}/csi-hostpath-plugin.yaml"

    # 5. StorageClass (csi-hostpath-sc) + VolumeSnapshotClass. ignoreFailedRead lets
    #    snapshots of a running PostgreSQL instance succeed despite transient reads.
    echo "   - Installing the StorageClass and VolumeSnapshotClass"
    kubectl apply -f "${csi_base}/examples/csi-storageclass.yaml"
    kubectl apply -f "${hostpath_dir}/csi-hostpath-snapshotclass.yaml"
    kubectl patch volumesnapshotclass csi-hostpath-snapclass --type merge \
        -p '{"parameters":{"ignoreFailedRead":"true"}}'

    # 6. Wait for the node plugin and controller to become ready.
    echo "   ⏳ Waiting for the CSI hostpath plugin to be ready..."
    kubectl rollout status statefulset/csi-hostpathplugin --timeout=300s
    kubectl rollout status deployment/snapshot-controller -n kube-system --timeout=300s

    echo "✅ CSI hostpath driver ready (StorageClass 'csi-hostpath-sc')."
}
