### Install Red Hat Openshift Logging and Loki Operator in the console

* Install the Operator using the default namespace.
  ```
  export CHANNEL="stable-5.6"
  
  curl https://raw.githubusercontent.com/pancongliang/openshift/main/operator/logging/deploy/lokistack/01_deploy_operator.yaml | envsubst | oc apply -f -
  
  export INSTALLPLAN_NAME_1=$(oc -n openshift-operators-redhat get installplans -o custom-columns=:metadata.name --no-headers)
  export INSTALLPLAN_NAME_2=$(oc -n openshift-logging get installplans -o custom-columns=:metadata.name --no-headers)
  
  oc -n openshift-operators-redhat patch installplan $INSTALLPLAN_NAME_1 -p '{"spec":{"approved":true}}' --type merge
  oc -n openshift-logging patch installplan $INSTALLPLAN_NAME_2 -p '{"spec":{"approved":true}}' --type merge
  ```
  
### Install and configure Loki Stack resource

#### Option A: Install lokistack using Minio Object Storage and NFS Storage Class

* Install and configure [Minio Object Storage and NFS Storage Class](https://github.com/pancongliang/openshift/blob/main/storage/minio/readme.md#options-c-deploying-minio-with-nfs-storageclass-as-the-backend-storage).
  If storageclass already exists, only [Minio Object Storage](https://github.com/pancongliang/openshift/blob/main/storage/minio/readme.md#options-b-deploying-minio-with-local-volume-as-the-backend-storage) will be installed.


* Create Object Storage secret credentials
  ```
  export MINIO_ADDR="http://minio-minio.apps.ocp4.example.com"
  export ACCESS_KEY_ID="minioadmin"
  export ACCESS_KEY_SECRET="minioadmin"
  export BUCKET_NAME="loki-bucket-minio"
  
  curl https://raw.githubusercontent.com/pancongliang/openshift/main/operator/logging/deploy/lokistack/02_minio_credentials.yaml | envsubst | oc apply -f -
  ```
  
* Create extra-small LokiStack ClusterLogging ClusterLogForwarder resource
  ```
  export STORAGECLASS_NAME="managed-nfs-storage"
  
  curl https://raw.githubusercontent.com/pancongliang/openshift/main/operator/logging/deploy/lokistack/03_deploy_loki_stack_minio.yaml | envsubst | oc apply -f -

  oc get po -n openshift-logging 
  ```




#### Option B: Install lokistack using ODF
* Install and configure [odf-operator](https://github.com/pancongliang/openshift/blob/main/storage/odf/deploy_high_availability_odf.md)

* Create ObjectBucketClaim
  ```
  export NAMESPACE="openshift-logging"
  export OBC_NAME="loki-bucket-odf"
  export GENERATEBUCKETNAME="${OBC_NAME}"
  export OBJECTBUCKETNAME="obc-${NAMESPACE}-${OBC_NAME}"
  
  curl https://raw.githubusercontent.com/pancongliang/openshift/main/operator/logging/deploy/lokistack/2_create_obc.yaml | envsubst | oc apply -f -
  ```
  
* Create Object Storage secret credentials
  1. Get bucket properties from the associated ConfigMap
  ```
  export BUCKET_HOST=$(oc get -n ${NAMESPACE} configmap ${OBC_NAME} -o jsonpath='{.data.BUCKET_HOST}')
  export BUCKET_NAME=$(oc get -n ${NAMESPACE} configmap ${OBC_NAME} -o jsonpath='{.data.BUCKET_NAME}')
  export BUCKET_PORT=$(oc get -n ${NAMESPACE} configmap ${OBC_NAME} -o jsonpath='{.data.BUCKET_PORT}')
  ```
  2. Get bucket access key from the associated Secret
  ```
  export ACCESS_KEY_ID=$(oc get -n ${NAMESPACE} secret ${OBC_NAME} -o jsonpath='{.data.AWS_ACCESS_KEY_ID}' | base64 -d)
  export SECRET_ACCESS_KEY=$(oc get -n ${NAMESPACE} secret ${OBC_NAME} -o jsonpath='{.data.AWS_SECRET_ACCESS_KEY}' | base64 -d)
  ```
  3. Create an Object Storage secret with keys as follows
  ```
  oc create -n ${NAMESPACE} secret generic ${OBC_NAME}-credentials \
     --from-literal=access_key_id="${ACCESS_KEY_ID}" \
     --from-literal=access_key_secret="${SECRET_ACCESS_KEY}" \
     --from-literal=bucketnames="${BUCKET_NAME}" \
     --from-literal=endpoint="https://${BUCKET_HOST}:${BUCKET_PORT}"
  ```
  
* Create LokiStack ClusterLogging ClusterLogForwarder resource
  ```
  curl https://raw.githubusercontent.com/pancongliang/openshift/main/operator/logging/deploy/lokistack/3_deploy_loki_stack_odf.yaml | envsubst | oc apply -f -

  oc get po -n openshift-logging 
  ```
