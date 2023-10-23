## Install and configure Red Hat Openshift Logging and Loki Operator


### Install Red Hat Openshift Logging and Loki Operator

* Install the Operator using the default namespace.
  ```
  export CHANNEL_NAME="stable-5.6"
  export CATALOG_SOURCE_NAME="redhat-operators"
  curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/operator/logging/lokistack/01-deploy-operator.yaml | envsubst | oc apply -f -
  
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
  export MINIO_ADDR="http://minio-minio.apps.ocp4.example.com"
  export ACCESS_KEY_ID="minioadmin"
  export ACCESS_KEY_SECRET="minioadmin"
  export BUCKET_NAME="loki-bucket"
  curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/operator/logging/lokistack/02-minio-credentials.yaml | envsubst | oc apply -f -
  ```
  
* Create extra-small LokiStack ClusterLogging ClusterLogForwarder resource
  ```
  export STORAGECLASS_NAME="managed-nfs-storage"
  curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/operator/logging/lokistack/03-deploy-loki-stack-minio.yaml | envsubst | oc apply -f -

  oc get po -n openshift-logging 
  ```


