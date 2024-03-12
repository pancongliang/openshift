## Install and configure Red Hat Openshift Logging and Loki Operator


### Install Red Hat Openshift Logging and Loki Operator

* Install the Operator using the default namespace.
  ```
  export CHANNEL_NAME="stable-5.6"
  export CATALOG_SOURCE_NAME="redhat-operators"
  curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/operator/logging/lokistack/01-deploy-operator.yaml | envsubst | oc apply -f -

  sleep 6
  
  oc patch installplan $(oc get ip -n openshift-operators-redhat  -o=jsonpath='{.items[?(@.spec.approved==false)].metadata.name}') -n openshift-operators-redhat --type merge --patch '{"spec":{"approved":true}}'
  oc patch installplan $(oc get ip -n openshift-logging  -o=jsonpath='{.items[?(@.spec.approved==false)].metadata.name}') -n openshift-logging --type merge --patch '{"spec":{"approved":true}}'

  oc get ip -n openshift-operators-redhat
  oc get ip -n openshift-logging
  ```
  
### Install and configure Loki Stack resource

#### Install lokistack using Minio Object Storage and NFS Storage Class

* Install and configure [Minio Object Storage and NFS Storage Class](https://github.com/pancongliang/openshift/blob/main/storage/minio/readme.md#options-c-deploying-minio-with-nfs-storageclass-as-the-backend-storage).
  If storageclass already exists, only [Minio Object Storage](https://github.com/pancongliang/openshift/blob/main/storage/minio/readme.md#options-b-deploying-minio-with-local-volume-as-the-backend-storage) will be installed.


* Create Object Storage secret credentials
  ```
  export MINIO_ADDR=$(oc get route minio -n minio -o jsonpath='http://{.spec.host}')
  export ACCESS_KEY_ID="minioadmin"
  export ACCESS_KEY_SECRET="minioadmin"
  export BUCKET_NAME="loki-bucket"
  curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/operator/logging/lokistack/02-minio-credentials.yaml | envsubst | oc apply -f -
  ```
  
* Create extra-small LokiStack ClusterLogging ClusterLogForwarder resource
  ```
  export STORAGE_CLASS_NAME="managed-nfs-storage"
  curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/operator/logging/lokistack/03-deploy-loki-stack.yaml | envsubst | oc apply -f -

  oc get po -n openshift-logging 
  ```

####  Install lokistack using ODF
* Install and configure [odf-operator](https://github.com/pancongliang/openshift/blob/main/storage/odf/readme.md)

* Create ObjectBucketClaim
   ```
   export NAMESPACE="openshift-logging"
   export OBC_NAME="loki-bucket-odf"
   export GENERATE_BUCKET_NAME="${OBC_NAME}"
   export OBJECT_BUCKET_NAME="obc-${NAMESPACE}-${OBC_NAME}"
   curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/operator/logging/lokistack/02-objectbucketclaim.yaml | envsubst | oc apply -f -
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
