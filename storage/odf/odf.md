## Deploy OpenShift Data Foundation using local storage devices


### Install and Configure Local Storage Operator
- Use the [Local Storage Operator](/storage/local-sc/readme.md) to create a local volume in block mode.
- Ensure the OCP cluster has at least three worker nodes or infrastructure nodes, each with at least one 100GB disk.

### Install Red Hat OpenShift Data Foundation

```
export CHANNEL_NAME="stable-4.16"

oc create -f - <<EOF 
apiVersion: v1
kind: Namespace
metadata:
  annotations:
    openshift.io/node-selector: ""
  labels:
    openshift.io/cluster-monitoring: "true"
  name: openshift-storage
spec: {}
---
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: openshift-storage-operatorgroup
  namespace: openshift-storage
spec:
  targetNamespaces:
  - openshift-storage
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: odf-operator
  namespace: openshift-storage
spec:
  channel: ${CHANNEL_NAME}
  installPlanApproval: "Automatic"
  name: odf-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF
```

### Add the `ocs` label to OCP nodes with storage devices
```
oc get nodes -l 'node-role.kubernetes.io/worker' -o name | xargs -I {} oc label {} cluster.ocs.openshift.io/openshift-storage=''
```

### Create StorageCluster
```
export LOCAL_PV_SIZE="100Gi"
export STORAGE_CLASS="local-block"

oc create -f - <<EOF 
apiVersion: ocs.openshift.io/v1
kind: StorageCluster
metadata:
  name: ocs-storagecluster
  namespace: openshift-storage
spec:
  manageNodes: false
  resources:
    mds:
      limits:
        cpu: "3"
        memory: "8Gi"
      requests:
        cpu: "3"
        memory: "8Gi"
  monDataDirHostPath: /var/lib/rook
  multiCloudGateway:
    disableLoadBalancerService: true
  storageDeviceSets:
  - count: 1  # Modify count to desired value. For each set of 3 disks increment the count by 1.
    dataPVCTemplate:
      spec:
        accessModes:
        - ReadWriteOnce
        resources:
          requests:
            storage: "${LOCAL_PV_SIZE}"  # This should be changed as per storage size. Minimum 100 GiB and Maximum 4 TiB
        storageClassName: ${STORAGE_CLASS}
        volumeMode: Block
    name: ocs-deviceset
    placement: {}
    portable: false
    replica: 3
    resources:
      limits:
        cpu: "2"
        memory: "5Gi"
      requests:
        cpu: "2"
        memory: "5Gi"
EOF
```

### Verify Installation
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
-  [Uninstalling](https://access.redhat.com/articles/6525111) OpenShift Data Foundation in Internal mode

### Reference Documentation
-  Install Red Hat OpenShift Data Foundation 4.X in [internal-attached mode](https://access.redhat.com/articles/5692201) using command line interface
-  Deploying [ODF CLI](https://openshift.blog/docs/openshift/ops/storage/odf-deploy-cli/)
-  Install Red Hat OpenShift Data Foundation 4.X in [internal mode](https://access.redhat.com/articles/5683981) using command line interface
