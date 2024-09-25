## Install and configure MCG

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

### Verifying the Installation
* Verifying the Installation
  ```
  $ oc get pods -n openshift-storage
  NAME                                               READY   STATUS    RESTARTS   AGE
  csi-addons-controller-manager-7fcdf7bfc8-j6h49     2/2     Running   0          76m
  noobaa-core-0                                      1/1     Running   0          4m8s
  noobaa-db-pg-0                                     1/1     Running   0          4m8s
  noobaa-default-backing-store-noobaa-pod-7a4dfe11   1/1     Running   0          2m3s
  noobaa-endpoint-64c49bc6c5-gvx2q                   1/1     Running   0          3m
  noobaa-operator-56b6f478b8-qbg8b                   1/1     Running   0          76m
  noobaa-pv-backing-store-noobaa-pod-7eb3176a        1/1     Running   0          2m54s
  noobaa-pv-backing-store-noobaa-pod-ddca8962        1/1     Running   0          2m54s
  ocs-metrics-exporter-595884c-xdx6d                 1/1     Running   0          76m
  ocs-operator-6f6b6dc894-hll7h                      1/1     Running   0          76m
  odf-console-97b6d585f-hprl6                        1/1     Running   0          76m
  odf-operator-controller-manager-84f6d8f9d6-wdnz2   2/2     Running   0          76m
  rook-ceph-operator-7cbcf4bdbf-dx8zc                1/1     Running   0          76m

  $ oc get storageclass openshift-storage.noobaa.io
  NAME                          PROVISIONER                       RECLAIMPOLICY   VOLUMEBINDINGMODE   ALLOWVOLUMEEXPANSION   AGE
  openshift-storage.noobaa.io   openshift-storage.noobaa.io/obc   Delete          Immediate           false                  2m8s
  
  $ oc get pvc -n openshift-storage
  NAME                                               STATUS   VOLUME                                     CAPACITY   ACCESS MODES   
  STORAGECLASS          AGE
  db-noobaa-db-pg-0                                  Bound    pvc-e929562a-e8a4-4821-b738-b17fed5767a1   50Gi       RWO            
  managed-nfs-storage   4m40s
  noobaa-default-backing-store-noobaa-pvc-7a4dfe11   Bound    pvc-9505f519-0027-4160-b479-bd1d52d109a9   50Gi       RWO            
  managed-nfs-storage   2m35s
  noobaa-pv-backing-store-noobaa-pvc-7eb3176a        Bound    pvc-fce5b9e5-f177-4b71-af04-ecde3b2f372a   100Gi      RWO            
  managed-nfs-storage   3m26s
  noobaa-pv-backing-store-noobaa-pvc-ddca8962        Bound    pvc-8b4d8e28-6c6c-45bc-bf5a-53069080e6b1   100Gi      RWO            
  managed-nfs-storage   3m26s

  $ oc get BackingStore -n openshift-storage
  NAME                           TYPE      PHASE   AGE
  noobaa-default-backing-store   pv-pool   Ready   3m10s
  noobaa-pv-backing-store        pv-pool   Ready   4m47s

  $ oc get noobaa -n openshift-storage
  NAME     S3-ENDPOINTS                       STS-ENDPOINTS                      IMAGE                                                                                                            PHASE   AGE
  noobaa   ["https://10.184.134.134:31063"]   ["https://10.184.134.134:32692"]   registry.redhat.io/odf4/mcg-core-rhel8@sha256:26a0f925ec82909caee0556c59856fd014397e3ccf4cd00bf82807c1a7cdc8b5   Ready   5m33s

  $ oc get bucketclass -n openshift-storage
  NAME                          PLACEMENT                                                        NAMESPACEPOLICY   QUOTA   PHASE   AGE
  noobaa-default-bucket-class   {"tiers":[{"backingStores":["noobaa-default-backing-store"]}]}                             Ready   4m32s
  ```

### Update BucketClass to use noobaa-pv-backing-store
* Update BucketClass to use noobaa-pv-backing-store
  ```
  oc patch bucketclass noobaa-default-bucket-class --patch '{"spec":{"placementPolicy":{"tiers":[{"backingStores":["noobaa-pv-backing-store"]}]}}}' --type merge -n openshift-storage
  ```


### Create ObjectBucketClaim and Object Storage secret 
* Create ObjectBucketClaim
   ```
   export NAMESPACE="openshift-logging"
   export OBC_NAME="loki-bucket-mcg"
   export GENERATE_BUCKET_NAME="${OBC_NAME}"
   export OBJECT_BUCKET_NAME="obc-${NAMESPACE}-${OBC_NAME}"
   curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/storage/mcg/04-objectbucketclaim.yaml | envsubst | oc apply -f -
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
* or  
   ```
   wget -q https://raw.githubusercontent.com/pancongliang/openshift/main/storage/mcg/05-config.yaml
   oc create secret generic ${OBC_NAME}-credentials --from-file=config.yaml=<(envsubst < 05-config.yaml) -n ${NAMESPACE}
   ```
