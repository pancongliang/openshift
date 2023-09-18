### Install Red Hat Openshift Logging and Loki Operator in the console

* Install the Operator using the default namespace.


### Install and configure Loki Stack resource

#### Option A: Install lokistack using Minio Object Storage and NFS Storage Class

* Install and configure [Minio Object Storage and NFS Storage Class](https://github.com/pancongliang/openshift/blob/main/storage/minio/readme.md)

* Create Object Storage secret credentials
  ~~~
  $ MINIO_ADDR="http://minio-minio.apps.ocp4.example.com"
  $ ACCESS_KEY_ID="minioadmin"
  $ ACCESS_KEY_SECRET="minioadmin"
  $ BUCKET_NAME="loki-bucket-minio"
  
  $ cat << EOF | envsubst | oc apply -f -
  apiVersion: v1
  kind: Secret
  metadata:
    name: ${BUCKET_NAME}-credentials
    namespace: openshift-logging
  stringData:
    access_key_id: ${ACCESS_KEY_ID}
    access_key_secret: ${ACCESS_KEY_SECRET}
    bucketnames: ${BUCKET_NAME}
    endpoint: ${MINIO_ADDR}
    region: minio
  EOF
  ~~~
  
* Create LokiStack ClusterLogging ClusterLogForwarder resource
  ~~~
  $ STORAGECLASS_NAME="managed-nfs-storage"
  
  $ cat << EOF | envsubst | oc apply -f -
  apiVersion: loki.grafana.com/v1
  kind: LokiStack
  metadata:
    name: logging-loki
    namespace: openshift-logging
  spec:
    size: 1x.extra-small
    storageClassName: ${STORAGECLASS_NAME}
    storage:
      secret:
        name: ${BUCKET_NAME}-credentials
        type: s3
    tenants:
      mode: openshift-logging    
  ---
  apiVersion: logging.openshift.io/v1
  kind: ClusterLogging
  metadata:
    name: instance
    namespace: openshift-logging
  spec:
    managementState: Managed
    logStore:
      type: lokistack
      lokistack:
        name: logging-loki
    collection:
      type: vector
  ---
  apiVersion: logging.openshift.io/v1
  kind: ClusterLogForwarder
  metadata:
    name: instance
    namespace: openshift-logging
  spec:
    pipelines: 
    - name: all-to-default
      inputRefs:
      - infrastructure
      - application
      - audit
      outputRefs:
      - default
  EOF
  ~~~


#### Option B: Install lokistack using ODF
* Install and configure [odf-operator](https://github.com/pancongliang/openshift/blob/main/storage/odf/deploy_high_availability_odf.md)

* Create ObjectBucketClaim
  ~~~
  $ NAMESPACE="openshift-logging"
  $ OBC_NAME="loki-bucket-odf"
  $ GENERATEBUCKETNAME="${OBC_NAME}"
  $ OBJECTBUCKETNAME="obc-${NAMESPACE}-${OBC_NAME}"
  
  $ cat << EOF | envsubst | oc apply -f -
  apiVersion: objectbucket.io/v1alpha1
  kind: ObjectBucketClaim
  metadata:
    finalizers:
    - objectbucket.io/finalizer
    labels:
      app: noobaa
      bucket-provisioner: openshift-storage.noobaa.io-obc
      noobaa-domain: openshift-storage.noobaa.io
    name: ${OBC_NAME}
    namespace: ${NAMESPACE}
  spec:
    additionalConfig:
      bucketclass: noobaa-default-bucket-class
    generateBucketName: ${GENERATEBUCKETNAME}
    objectBucketName: ${OBJECTBUCKETNAM}
    storageClassName: openshift-storage.noobaa.io
  EOF
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
  $ cat << EOF | envsubst | oc apply -f -
  apiVersion: loki.grafana.com/v1
  kind: LokiStack
  metadata:
    name: logging-loki
    namespace: openshift-logging
  spec:
    size: 1x.extra-small
    storageClassName: ocs-storagecluster-cephfs
    storage:
      secret:
        name: ${OBC_NAME}-credentials
        type: s3
    tenants:
      mode: openshift-logging    
  ---
  apiVersion: logging.openshift.io/v1
  kind: ClusterLogging
  metadata:
    name: instance
    namespace: openshift-logging
  spec:
    managementState: Managed
    logStore:
      type: lokistack
      lokistack:
        name: logging-loki
    collection:
      type: vector
  ---
  apiVersion: logging.openshift.io/v1
  kind: ClusterLogForwarder
  metadata:
    name: instance
    namespace: openshift-logging
  spec:
    pipelines: 
    - name: all-to-default
      inputRefs:
      - infrastructure
      - application
      - audit
      outputRefs:
      - default
  EOF
  ~~~
