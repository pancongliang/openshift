### Install Red Hat Openshift Logging and Loki Operator in the console
Install the Operator using the default namespace.


### Install Loki Stack resource

#### Option A: Install lokistack using minio and nfs sc
* Install [minio and nfs sc](https://github.com/pancongliang/openshift/blob/main/storage/minio/readme.md)

* Create Secret LokiStack ClusterLogging ClusterLogForwarder resource
~~~
MINIO_ADDR="http://minio-minio.apps.ocp4.example.com"
ACCESS_KEY_ID="minioadmin"
ACCESS_KEY_SECRET="minioadmin"
BUCKET_NAME="loki-bucket-minio"

$ cat << EOF | envsubst | oc apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: ${BUCKET_NAME}--credentials
  namespace: openshift-logging
stringData:
  access_key_id: ${ACCESS_KEY_ID}
  access_key_secret: ${ACCESS_KEY_SECRET}
  bucketnames: ${BUCKET_NAME}
  endpoint: ${MINIO_ADDR}
  region: minio
EOF

$ oc create -f https://raw.githubusercontent.com/pancongliang/openshift/main/operator/logging/deploy/deploy_loki_using_minio.yaml
~~~

#### Option B: Install lokistack using ODF
* Install and configure [odf-operator](https://github.com/pancongliang/openshift/blob/main/storage/odf/deploy_odf_on_single_node.md)

1. Create ObjectBucketClaim
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

2. Create Object Storage secret
* Get bucket properties from the associated ConfigMap
~~~
$ BUCKET_HOST=$(oc get -n ${NAMESPACE} configmap ${OBC_NAME} -o jsonpath='{.data.BUCKET_HOST}')
$ BUCKET_NAME=$(oc get -n ${NAMESPACE} configmap ${OBC_NAME} -o jsonpath='{.data.BUCKET_NAME}')
$ BUCKET_PORT=$(oc get -n ${NAMESPACE} configmap ${OBC_NAME} -o jsonpath='{.data.BUCKET_PORT}')
~~~
* Get bucket access key from the associated Secret
~~~
$ ACCESS_KEY_ID=$(oc get -n ${NAMESPACE} secret ${OBC_NAME} -o jsonpath='{.data.AWS_ACCESS_KEY_ID}' | base64 -d)
$ SECRET_ACCESS_KEY=$(oc get -n ${NAMESPACE} secret ${OBC_NAME} -o jsonpath='{.data.AWS_SECRET_ACCESS_KEY}' | base64 -d)
~~~
* Create an Object Storage secret with keys as follows
~~~
$ oc create -n ${NAMESPACE} secret generic ${OBC_NAME}-credentials \
   --from-literal=access_key_id="${ACCESS_KEY_ID}" \
   --from-literal=access_key_secret="${SECRET_ACCESS_KEY}" \
   --from-literal=bucketnames="${BUCKET_NAME}" \
   --from-literal=endpoint="https://${BUCKET_HOST}:${BUCKET_PORT}"
~~~

3. Create LokiStack ClusterLogging ClusterLogForwarder resource
~~~
$ STORAGECLASS_NAME=$(oc get sc openshift-storage.noobaa.io -o custom-columns=NAME:.metadata.name --no-headers)
$ curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/operator/logging/deploy/deploy_loki_using_odf.yaml | envsubst | oc apply -f -
~~~
