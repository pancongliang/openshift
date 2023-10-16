### Install quay operator

* Install the Operator using the default namespace.
  ```
  export CHANNEL_NAME="stable-3.9"
  export CATALOG_SOURCE_NAME="redhat-operators"
  
  curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/operator/quay/01_deploy_operator.yaml | envsubst | oc apply -f -

  oc patch installplan $(oc get ip -n openshift-operators  -o=jsonpath='{.items[?(@.spec.approved==false)].metadata.name}') -n openshift-operators-redhat --type merge --patch '{"spec":{"approved":true}}'
  ```

### Create Object Storage secret credentials

* Create quay namespace.
  ```
  export NAMESPACE=quay-enterprise
  oc new-project ${NAMESPACE}
  ```

* Create a configuration file that contains access to the MinIO Bucket.
  ```
  export MINIO_ADDR="http://minio-minio.apps.ocp4.example.com"
  export ACCESS_KEY_ID="minioadmin"
  export ACCESS_KEY_SECRET="minioadmin"
  export BUCKET_NAME="quat-bucket"

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

* Create Secret based on configuration file.
  ```
  oc create secret generic --from-file config.yaml=./config.yaml config-bundle-secret -n ${NAMESPACE}
  ```
  
### Create Quay Registry
  
  ```
  curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/operator/quay/02_create_quay_registry.yaml | envsubst | oc apply -f -
  ```
