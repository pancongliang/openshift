## Install and configure Red Hat Openshift Logging and Loki Operator


### Install Red Hat Openshift Logging and Loki Operator

* If the operator version is 5.9 or below
  ```
  export CHANNEL_NAME="stable-5.9"
  export CATALOG_SOURCE_NAME="redhat-operators"
  export NAMESPACE=("openshift-logging" "openshift-operators-redhat")
  curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/operator/logging/lokistack/01-operator.yaml | envsubst | oc create -f -
  for i in {1..2}; do curl -s https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/operator/approve_ip.sh | bash; done
  ```
* If the operator version is 6.0 or above
  ```
  export CHANNEL_NAME="stable-6.1"
  export CATALOG_SOURCE_NAME="redhat-operators"
  export NAMESPACE=("openshift-logging" "openshift-operators-redhat" "openshift-operators")
  curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/operator/logging/lokistack/01-operator-v6.yaml | envsubst | oc create -f -
  curl -s https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/operator/approve_ip.sh
  ```

  
### Install and configure Loki Stack resource

#### Install Minio Object Storage and NFS Storage Class

* Install and configure [Minio Object Storage and NFS Storage Class](https://github.com/pancongliang/openshift/blob/main/storage/minio/readme.md#options-c-deploying-minio-with-nfs-storageclass-as-the-backend-storage).
  If storageclass already exists, only [Minio Object Storage](https://github.com/pancongliang/openshift/blob/main/storage/minio/readme.md#options-b-deploying-minio-with-local-volume-as-the-backend-storage) will be installed.


* Create Object Storage secret credentials
  ```
  export BUCKET_HOST=$(oc get route minio -n minio -o jsonpath='http://{.spec.host}')
  export ACCESS_KEY_ID="minioadmin"
  export ACCESS_KEY_SECRET="minioadmin"
  export BUCKET_NAME="loki-bucket"
  curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/operator/logging/lokistack/02-config.yaml | envsubst | oc create -f -
  ```

#### Install and configure Loki Stack resource
  
* If the operator version is 5.9 or below, create the LokiStack ClusterLogging ClusterLogForwarder resource as follows
  ```
  export STORAGE_CLASS_NAME="managed-nfs-storage"
  curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/operator/logging/lokistack/03-loki-stack.yaml | envsubst | oc create -f -

  oc get po -n openshift-logging 
  ```

* If the operator version is 6.0 or above, create the LokiStack ClusterLogging ClusterLogForwarder resource as follows:
  ```
  export STORAGE_CLASS_NAME="managed-nfs-storage"
  curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/operator/logging/lokistack/03-loki-stack-v6.yaml | envsubst | oc create -f -
  oc get po -n openshift-logging

  oc create sa collector -n openshift-logging
  oc adm policy add-cluster-role-to-user logging-collector-logs-writer -z collector
  oc project openshift-logging
  oc adm policy add-cluster-role-to-user collect-application-logs -z collector
  oc adm policy add-cluster-role-to-user collect-audit-logs -z collector
  oc adm policy add-cluster-role-to-user collect-infrastructure-logs -z collector

  curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/operator/logging/lokistack/04-clf-ui.yaml | envsubst | oc create -f -
  ```

####  Install lokistack using ODF or MCG/NFS-SC
* Install and configure [odf-operator](https://github.com/pancongliang/openshift/blob/main/storage/odf/readme.md)
* Install and configure [nfs-sc](https://github.com/pancongliang/openshift/tree/main/storage/nfs-storageclass) and [MCG](https://github.com/pancongliang/openshift/blob/main/storage/mcg/readme.md)
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
  export STORAGE_CLASS_NAME="ocs-storagecluster-cephfs"  # or  managed-nfs-storage
  export BUCKET_NAME="${OBC_NAME}"
  curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/operator/logging/lokistack/03-loki-stack-odf.yaml | envsubst | oc apply -f -
   ```
