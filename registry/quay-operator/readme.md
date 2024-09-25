## Install and configure quay operator

### Install quay operator

* Install the Operator using the default namespace.
  ```
  export CHANNEL_NAME="stable-3.9"
  export CATALOG_SOURCE_NAME="redhat-operators"
  curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/registry/quay-operator/01-deploy-operator.yaml | envsubst | oc apply -f -

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

* Create a configuration file that contains access to the MinIO Bucket.
  ```
  export BUCKET_HOST=$(oc get route minio -n minio -o jsonpath='{.spec.host}')
  export ACCESS_KEY_ID="minioadmin"
  export ACCESS_KEY_SECRET="minioadmin"
  export BUCKET_NAME="quay-bucket"

  wget -q https://raw.githubusercontent.com/pancongliang/openshift/main/registry/quay-operator/02-config.yaml
  ```

* Create Secret based on config.yaml file.
  ```
  oc create secret generic config-bundle-secret --from-file=config.yaml=<(envsubst < 02-config.yaml) -n ${NAMESPACE}
  ```

### Create Quay Registry 

* Create quay registry 
  ```
  curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/registry/quay-operator/03-quay-registry.yaml | envsubst | oc apply -f -
  ```

* View deployed resources
  ```
  oc get po -n ${NAMESPACE}
  NAME                                                  READY   STATUS      RESTARTS        AGE
  example-registry-clair-app-76b7ff45d7-bcf6p           1/1     Running     2 (3m16s ago)   3m23s
  example-registry-clair-app-76b7ff45d7-fwtc5           1/1     Running     0               2m52s
  example-registry-clair-postgres-7dc5878c9c-nlbss      1/1     Running     1 (3m7s ago)    3m24s
  example-registry-quay-app-7f48f6cd5c-qctbs            1/1     Running     0               3m23s
  example-registry-quay-app-7f48f6cd5c-vvczh            1/1     Running     0               3m14s
  example-registry-quay-app-upgrade-vt5qq               0/1     Completed   2               4m40s
  example-registry-quay-config-editor-75746c469-7wm7w   1/1     Running     0               3m23s
  example-registry-quay-database-8f56fc565-kj4p4        1/1     Running     0               3m21s
  example-registry-quay-mirror-7bc5bdb4b6-mz9gf         1/1     Running     0               2m52s
  example-registry-quay-mirror-7bc5bdb4b6-nlqmp         1/1     Running     0               2m52s
  example-registry-quay-redis-7b5d45977b-6b6mv          1/1     Running     0               3m24s

  oc get pvc -n ${NAMESPACE}
  NAME                                 STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS          
  AGE
  example-registry-clair-postgres-13   Bound    pvc-48c28a8c-eb69-409c-9192-2e07f6fcf5bc   50Gi       RWO            managed-nfs-storage   33m
  example-registry-quay-postgres-13    Bound    pvc-b2a41123-480b-4e37-837f-29d7a1550553   50Gi       RWO            managed-nfs-storage   35m
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
