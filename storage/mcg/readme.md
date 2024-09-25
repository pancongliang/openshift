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


### Create SC
* Deploy [NFS StorageClass](https://github.com/pancongliang/openshift/blob/main/storage/nfs-storageclass/readme.md), if storage class has been deployed,only need to set the variables.

### Create Noobaa
* Create Noobaa
  ```
  curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/storage/mcg/02-noobaa.yaml | envsubst | oc create -f -
  ```

### Create BackingStore
* Create BackingStore after specifying variables
  ```
  export PVC_SIZE=100Gi
  export STORAGE_CLASS_NAME=managed-nfs-storage
  curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/storage/mcg/03-backing-store.yaml | envsubst | oc create -f -
  ```

### Update BucketClass to use noobaa-pv-backing-store
* Update BucketClass to use noobaa-pv-backing-store
  ```
  oc patch bucketclass noobaa-default-bucket-class --patch '{"spec":{"placementPolicy":{"tiers":[{"backingStores":["noobaa-pv-backing-store"]}]}}}' --type merge -n openshift-storage
  ```
  
### Verifying the Installation
* Verifying the Installation
  ```
  oc get pods -n openshift-storage

  oc get storageclass openshift-storage.noobaa.io

  oc get pvc -n openshift-storage

  oc get BackingStore -n openshift-storage

  oc get noobaa -n openshift-storage

  oc get bucketclass -n openshift-storage

  ```
