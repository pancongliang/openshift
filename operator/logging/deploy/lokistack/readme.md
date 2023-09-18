### Install Red Hat Openshift Logging and Loki Operator in the console

* Install the Operator using the default namespace.


### Install and configure Loki Stack resource

#### Option A: Install lokistack using Minio Object Storage and NFS Storage Class

* Install and configure [Minio Object Storage and NFS Storage Class](https://github.com/pancongliang/openshift/blob/main/storage/minio/readme.md#options-c-deploying-minio-with-nfs-storageclass-as-the-backend-storage)

* Create Object Storage secret credentials
  ~~~
  $ MINIO_ADDR="http://minio-minio.apps.ocp4.example.com"
  $ ACCESS_KEY_ID="minioadmin"
  $ ACCESS_KEY_SECRET="minioadmin"
  $ BUCKET_NAME="loki-bucket-minio"
  $ curl https://raw.githubusercontent.com/pancongliang/openshift/main/operator/logging/deploy/lokistack/01_minio_credentials.yaml | envsubst | oc apply -f -
  ~~~
  
* Create extra-small LokiStack ClusterLogging ClusterLogForwarder resource
  ~~~
  $ STORAGECLASS_NAME="managed-nfs-storage"
  $ curl https://raw.githubusercontent.com/pancongliang/openshift/main/operator/logging/deploy/lokistack/02_deploy_loki_stack_minio.yaml | envsubst | oc apply -f -
  ~~~




#### Option B: Install lokistack using ODF
* Install and configure [odf-operator](https://github.com/pancongliang/openshift/blob/main/storage/odf/deploy_high_availability_odf.md)

* Create ObjectBucketClaim
  ~~~
  $ NAMESPACE="openshift-logging"
  $ OBC_NAME="loki-bucket-odf"
  $ GENERATEBUCKETNAME="${OBC_NAME}"
  $ OBJECTBUCKETNAME="obc-${NAMESPACE}-${OBC_NAME}"
  $ curl https://raw.githubusercontent.com/pancongliang/openshift/main/operator/logging/deploy/lokistack/01_create_obc.yaml | envsubst | oc apply -f -
  ~~~
  
* Create Object Storage secret credentials
  1. Get bucket properties from the associated ConfigMap
  ~~~
  $ BUCKET_HOST=$(oc get -n ${NAMESPACE} configmap ${OBC_NAME} -o jsonpath='{.data.BUCKET_HOST}')
  $ BUCKET_NAME=$(oc get -n ${NAMESPACE} configmap ${OBC_NAME} -o jsonpath='{.data.BUCKET_NAME}')
  $ BUCKET_PORT=$(oc get -n ${NAMESPACE} configmap ${OBC_NAME} -o jsonpath='{.data.BUCKET_PORT}')
  ~~~
  2. Get bucket access key from the associated Secret
  ~~~
  $ ACCESS_KEY_ID=$(oc get -n ${NAMESPACE} secret ${OBC_NAME} -o jsonpath='{.data.AWS_ACCESS_KEY_ID}' | base64 -d)
  $ SECRET_ACCESS_KEY=$(oc get -n ${NAMESPACE} secret ${OBC_NAME} -o jsonpath='{.data.AWS_SECRET_ACCESS_KEY}' | base64 -d)
  ~~~
  3. Create an Object Storage secret with keys as follows
  ~~~
  $ oc create -n ${NAMESPACE} secret generic ${OBC_NAME}-credentials \
     --from-literal=access_key_id="${ACCESS_KEY_ID}" \
     --from-literal=access_key_secret="${SECRET_ACCESS_KEY}" \
     --from-literal=bucketnames="${BUCKET_NAME}" \
     --from-literal=endpoint="https://${BUCKET_HOST}:${BUCKET_PORT}"
  ~~~
  
* Create LokiStack ClusterLogging ClusterLogForwarder resource
  ~~~
  $ curl https://raw.githubusercontent.com/pancongliang/openshift/main/operator/logging/deploy/lokistack/02_deploy_loki_stack_odf.yaml | envsubst | oc apply -f -
  ~~~
