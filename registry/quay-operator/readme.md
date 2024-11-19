## Install and configure quay operator

### Install quay operator

* Install the Operator using the default namespace.
  ```
  export CHANNEL_NAME="stable-3.13"
  export CATALOG_SOURCE_NAME="redhat-operators"
  curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/registry/quay-operator/01-operator.yaml | envsubst | oc apply -f -
  sleep 20

  oc patch installplan $(oc get ip -n openshift-operators -o=jsonpath='{.items[?(@.spec.approved==false)].metadata.name}') -n openshift-operators --type merge --patch '{"spec":{"approved":true}}'
  oc get ip -n openshift-operators
  ```

### Deploy NFS Storage Class and Minio Object Storage

* Deploy [NFS Storage Class](https://github.com/pancongliang/openshift/blob/main/storage/nfs-storageclass/readme.md)
  - Postgres database requires two 50 GiB PVs, so deploy nfs storage class.

* Deploy [Minio Object Storage](https://github.com/pancongliang/openshift/blob/main/storage/minio/readme.md#options-c-deploying-minio-with-nfs-storageclass-as-the-backend-storage) and create a bucket named `quay-bucket`
  - Quay uses object storage by default, so deploy Minio object storage.

### Create Object Storage secret

* Create quay namespace.
  ```
  export NAMESPACE=quay-enterprise
  oc new-project ${NAMESPACE}
  ```

* Create a secret that contains access to the MinIO Bucket.
  ```
  export BUCKET_HOST=$(oc get route minio -n minio -o jsonpath='{.spec.host}')
  export ACCESS_KEY_ID="minioadmin"
  export ACCESS_KEY_SECRET="minioadmin"
  export BUCKET_NAME="quay-bucket"

  wget -q https://raw.githubusercontent.com/pancongliang/openshift/main/registry/quay-operator/02-config.yaml
  oc create secret generic quay-config --from-file=config.yaml=<(envsubst < 02-config.yaml) -n ${NAMESPACE}
  ```

### Create Quay Registry 

* The replica count for Quay, Clair, and Mirror pods
  ```
  export REPLICAS=1   # 1 or 2
  ```
* Create quay registry
  ```
  curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/registry/quay-operator/03-quay-registry.yaml | envsubst | oc create -f -
  ```

* View deployed resources
  ```
  oc get po -n ${NAMESPACE}
  oc get pvc -n ${NAMESPACE}
  ```

### Access the quay console and create a user

* Access the quay console
  ```
  oc get route example-registry-quay -n ${NAMESPACE} -o jsonpath='{.spec.host}'
  ```

* Click `Create Account` to create `quayadmin` user in the quay console page
  
* Push the image to quay registry
  ```
  export QUAY_HOST=$(oc get route example-registry-quay -n ${NAMESPACE} -o jsonpath='{.spec.host}')
  export PASSWORD="password"
  podman login -u quayadmin -p ${PASSWORD} ${QUAY_HOST}

  podman pull quay.io/redhattraining/hello-world-nginx:v1.0
  podman tag quay.io/redhattraining/hello-world-nginx:v1.0 ${QUAY_HOST}/quayadmin/hello-world-nginx:v1.0
  podman push ${QUAY_HOST}/quayadmin/hello-world-nginx:v1.0 --tls-verify=false
  ```
