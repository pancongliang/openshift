### Install quay operator

* Install the Operator using the default namespace.
  ```
  export CHANNEL_NAME="stable-3.9"
  export CATALOG_SOURCE_NAME="redhat-operators"
  curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/operator/quay/01-deploy-operator.yaml | envsubst | oc apply -f -

  oc patch installplan $(oc get ip -n openshift-operators -o=jsonpath='{.items[?(@.spec.approved==false)].metadata.name}') -n openshift-operators --type merge --patch '{"spec":{"approved":true}}'
  ```

### Deploy Minio Object Storage

* Deploy [Minio Object Storage](https://github.com/pancongliang/openshift/blob/main/storage/minio/readme.md)

### Create Object Storage secret

* Create a configuration file that contains access to the MinIO Bucket.
  ```
  export MINIO_ADDR="http://minio-minio.apps.ocp4.example.com"
  export ACCESS_KEY_ID="minioadmin"
  export ACCESS_KEY_SECRET="minioadmin"
  export BUCKET_NAME="quay-bucket"

  cat > config.yaml << EOF
  DISTRIBUTED_STORAGE_CONFIG: 
    default: 
      - RadosGWStorage 
      - access_key: ${ACCESS_KEY_ID}
        secret_key: ${ACCESS_KEY_SECRET}
        bucket_name: ${BUCKET_NAME}
        hostname: ${MINIO_ADDR}
        is_secure: false
        storage_path: /
  DISTRIBUTED_STORAGE_DEFAULT_LOCATIONS: [] 
  DISTRIBUTED_STORAGE_PREFERENCE: 
      - default
  EOF
  ```
  
* Create quay namespace.
  ```
  export NAMESPACE=quay-enterprise
  oc new-project ${NAMESPACE}
  ```

* Create Secret based on configuration file.
  ```
  oc create secret generic --from-file config.yaml=./config.yaml config-bundle-secret -n ${NAMESPACE}
  ```

### Create Quay Registry 

* Create quay registry 
  ```
  curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/operator/quay/02-create-quay-registry.yaml | envsubst | oc apply -f -
  ```

* View deployed resources
  ```
  oc get po -n ${NAMESPACE}
  ```

### Access the quay console and create a user

* View quay route
  ```
  QUAY_HOST=$(oc get route example-registry-quay -n redhat-quay -o jsonpath='{.spec.host}')
  ```
* Enter the address in the "QUAY_HOST" variable into browser

* Click `Create Account` to create `quayadmin` user. 
  
* Push the image to quay registry
  ```
  podman login -u quayadmin -p password ${QUAY_HOST}
  podman tag quay.io/redhattraining/hello-world-nginx:v1.0 ${QUAY_HOST}/quayadmin/hello-world-nginx:v1.0
  pomdan push ${QUAY_HOST}/quayadmin/hello-world-nginx:v1.0 –tls-verify=false
  ```
