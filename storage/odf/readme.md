## Deploy OpenShift Data Foundation using local storage devices


### Install and Configure Local Storage Operator
- Use the [Local Storage Operator](/storage/local-sc/readme.md) to create a local volume in block mode.
- Ensure the OCP cluster has at least three worker nodes or infrastructure nodes, each with at least one 100GB disk.

### Install Red Hat OpenShift Data Foundation
- Install the Operator using the default namespace:
  ```
  export CHANNEL_NAME="stable-4.16"
  export CATALOG_SOURCE_NAME="redhat-operators"
  export NAMESPACE="openshift-storage"
  curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/storage/odf/01-operator.yaml | envsubst | oc create -f -
  curl -s https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/operator/approve_ip.sh | bash
  ```

### Label Nodes with Storage Devices
- Add the `ocs` label to OCP nodes with storage devices:
  ```
  oc get nodes -l 'node-role.kubernetes.io/worker' -o name | xargs -I {} oc label {} cluster.ocs.openshift.io/openshift-storage=''
  ```

### Create StorageCluster
- Create the StorageCluster by specifying variables:
  ```
  export LOCAL_PV_SIZE="100Gi"
  export STORAGE_CLASS_NAME="local-block"
  curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/storage/odf/02-storagecluster.yaml | envsubst | oc create -f -
  ```

### Verify Installation
- Check the status of ODF pods and storage classes:
  ```
  $ oc get pods -n openshift-storage

  $ oc get sc
  local-block                   kubernetes.io/no-provisioner            Delete  WaitForFirstConsumer   false 7m16s
  ocs-storagecluster-ceph-rbd   openshift-storage.rbd.csi.ceph.com      Delete  Immediate              true  8m  # Block storage
  ocs-storagecluster-ceph-rgw   openshift-storage.ceph.rook.io/bucket   Delete  Immediate              false 9m  # RGW Object storage
  ocs-storagecluster-cephfs     openshift-storage.cephfs.csi.ceph.com   Delete  Immediate              true  8m  # FS storage
  openshift-storage.noobaa.io   openshift-storage.noobaa.io/obc         Delete  Immediate              false 8m  # NooBaa Object storage
  ```


### Uninstalling OpenShift Data Foundation
-  [Uninstalling OpenShift Data Foundation in Internal mode](https://access.redhat.com/articles/6525111)

### Reference Documentation
-  [Install Red Hat OpenShift Data Foundation 4.X in internal-attached mode using command line interface](https://access.redhat.com/articles/5692201)

-  [Install Red Hat OpenShift Data Foundation 4.X in internal mode using command line interface](https://access.redhat.com/articles/5683981)
