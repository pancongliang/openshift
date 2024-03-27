## Install and configure ODF

### Install and configure local storage operator
* Install and configure [local storage operator](https://github.com/pancongliang/openshift/blob/main/storage/local-sc/readme.md).
* There must be at least three worker nodes or infrastructure nodes in the OCP cluster. Each node should contain 1 disk and require 3 disks (PV), each disk is at least 100GB.
  
### Install Red Hat OpenShift Data Foundation
* Install the Operator using the default namespace
  ```
  export CHANNEL_NAME="stable-4.12"
  export CATALOG_SOURCE_NAME="redhat-operators"
  curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/storage/mcg/01-operator.yaml | envsubst | oc create -f -

  sleep 12
  
  oc patch installplan $(oc get ip -n openshift-storage -o=jsonpath='{.items[?(@.spec.approved==false)].metadata.name}') -n openshift-storage --type merge --patch '{"spec":{"approved":true}}'

  oc get ip -n openshift-storage
  ```


### Add a label to the node where the disk is added
* The ocs label needs to be added to each ocp node that has a storage device. ODF operators look for this label to learn which nodes can be targeted for scheduling by ODF components.
* If the label has been marked during the configuration of `local storage operator`, can skip it.
  ```
  export NODE_NAME01=worker01.ocp4.example.com
  oc label node ${NODE_NAME01} cluster.ocs.openshift.io/openshift-storage=''

  export NODE_NAME02=worker02.ocp4.example.com
  oc label node ${NODE_NAME02} cluster.ocs.openshift.io/openshift-storage=''

  export NODE_NAME03=worker03.ocp4.example.com
  oc label node ${NODE_NAME03} cluster.ocs.openshift.io/openshift-storage=''
  ```

### Create StorageCluster
* Create StorageCluster after specifying variables
  ```
  export LOACL_PV_SIZE=100Gi  # This should be changed as per storage size. Minimum 100 GiB and Maximum 4 TiB
  export STORAGE_CLASS_NAME=localblock
  curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/storage/odf/02-storagecluster.yaml | envsubst | oc create -f -
  ```

### Verifying the Installation
* Verifying the Installation
  ```
  oc get pods -n openshift-storage

  oc get sc
  ocs-storagecluster-ceph-rbd   openshift-storage.rbd.csi.ceph.com      Delete  Immediate  true  8m  # Block storage
  ocs-storagecluster-ceph-rgw   openshift-storage.ceph.rook.io/bucket   Delete  Immediate  false 9m  # RGW Object storage
  ocs-storagecluster-cephfs     openshift-storage.cephfs.csi.ceph.com   Delete  Immediate  true  8m  # FS storage
  openshift-storage.noobaa.io   openshift-storage.noobaa.io/obc         Delete  Immediate  false 8m  # NooBaa Object storage
  ```
