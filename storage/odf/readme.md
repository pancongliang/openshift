## Install and configure ODF

### Install and configure local storage operator
* Install and configure [local storage operator](https://github.com/pancongliang/openshift/blob/main/storage/local-sc/readme.md).
* There must be at least three worker nodes or infrastructure nodes in the OCP cluster. Each node should contain 1 disk and require 3 disks (PV), each disk is at least 100GB.
  
### Install Red Hat OpenShift Data Foundation
* Install the Operator using the default namespace
  ```
  export CHANNEL_NAME="stable-4.12"
  export CATALOG_SOURCE_NAME="redhat-operators"
  curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/storage/odf/01-operator.yaml | envsubst | oc create -f -

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
    
* Use `ocs-storagecluster-cephfs` sc to create filesystem pvc and mount
  ```
  oc new-project test
  oc new-app --name=mysql \
   --docker-image registry.access.redhat.com/rhscl/mysql-57-rhel7:latest \
   -e MYSQL_USER=user1 -e MYSQL_PASSWORD=mypa55 -e MYSQL_DATABASE=testdb \
   -e MYSQL_ROOT_PASSWORD=r00tpa55

  oc set volumes deployment/mysql \
   --add --name mysql-storage --type pvc --claim-class ocs-storagecluster-cephfs \
   --claim-mode RWO --claim-size 10Gi --mount-path /var/lib/mysql/data \
   --claim-name mysql-storage

  export POD_NAME=$(oc get pods -n test -o=jsonpath='{.items[*].metadata.name}')
  oc -n test rsh ${POD_NAME} df -h |grep "/var/lib/mysql/data"
  ```

### Create ObjectBucketClaim and Object Storage secret 
* Create ObjectBucketClaim
   ```
   export NAMESPACE="openshift-logging"
   export OBC_NAME="loki-bucket-odf"
   export GENERATE_BUCKET_NAME="${OBC_NAME}"
   export OBJECT_BUCKET_NAME="obc-${NAMESPACE}-${OBC_NAME}"
   curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/storage/odf/03-objectbucketclaim.yaml | envsubst | oc apply -f -
   ```

* Create Object Storage secret

  Get bucket properties from the associated ConfigMap
   ```
   export BUCKET_HOST=$(oc get -n ${NAMESPACE} configmap ${OBC_NAME} -o jsonpath='{.data.BUCKET_HOST}')
   export BUCKET_NAME=$(oc get -n ${NAMESPACE} configmap ${OBC_NAME} -o jsonpath='{.data.BUCKET_NAME}')
   export BUCKET_PORT=$(oc get -n ${NAMESPACE} configmap ${OBC_NAME} -o jsonpath='{.data.BUCKET_PORT}')
   ```
  Get bucket access key from the associated Secret
   ```
   export ACCESS_KEY_ID=$(oc get -n ${NAMESPACE} secret ${OBC_NAME} -o jsonpath='{.data.AWS_ACCESS_KEY_ID}' | base64 -d)
   export SECRET_ACCESS_KEY=$(oc get -n ${NAMESPACE} secret ${OBC_NAME} -o jsonpath='{.data.AWS_SECRET_ACCESS_KEY}' | base64 -d)
   ```

* Create an Object Storage secret with keys as follows
   ```
   oc create -n ${NAMESPACE} secret generic ${OBC_NAME}-credentials \
      --from-literal=access_key_id="${ACCESS_KEY_ID}" \
      --from-literal=access_key_secret="${SECRET_ACCESS_KEY}" \
      --from-literal=bucketnames="${BUCKET_NAME}" \
      --from-literal=endpoint="https://${BUCKET_HOST}:${BUCKET_PORT}"
   ```

* Create extra-small LokiStack ClusterLogging ClusterLogForwarder resource
   ```
  export STORAGE_CLASS_NAME="ocs-storagecluster-cephfs"
  export BUCKET_NAME"${OBC_NAME}"
  curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/operator/logging/lokistack/03-deploy-loki-stack.yaml | envsubst | oc apply -f -
   ```

