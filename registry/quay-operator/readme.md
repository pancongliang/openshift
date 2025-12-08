## Install and configure quay operator

### Install quay operator

* Install the Operator using the default namespace.
  ```
  export SUB_CHANNEL="stable-3.13"
  export CATALOG_SOURCE="redhat-operators"
  export NAMESPACE="openshift-operators"
  curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/registry/quay-operator/01-operator.yaml | envsubst | oc apply -f -
  curl -s https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/operator/approve_ip.sh | bash
  ```

### Deploy NFS Storage Class and Minio Object Storage

* Deploy [NFS Storage Class](/storage/nfs-sc/readme.md)
  - Postgres database requires two 50 GiB PVs, so deploy nfs storage class.

* Deploy [Minio Object Storage](/storage/minio/readme.md) and create a bucket named `quay-bucket`
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

  curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/registry/quay-operator/02-config.yaml | envsubst | oc create secret generic quay-config --from-file=config.yaml=/dev/stdin -n ${NAMESPACE}
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


### Option: Change quay config

* Export quay-config file
  ```
  QUAY_REGISTRY_NAME=$(oc get quayregistries -n ${NAMESPACE} -o jsonpath='{.items[0].metadata.name}')
  CONFIG_BUNDLE_SECRET=$(oc get quayregistry example-registry -n ${NAMESPACE} -o jsonpath='{.spec.configBundleSecret}')
  oc get secret $CONFIG_BUNDLE_SECRET -o json | jq '.data."config.yaml"' | cut -d '"' -f2 | base64 -d > config.yaml
  ```
  
* Update config.yaml file
  ```
  vim config.yaml
  ```

* Replace the key config.yaml in the existing Secret with the content of the new config.yaml file
  ```
  oc set data secret/$CONFIG_BUNDLE_SECRET --from-file=config.yaml=config.yaml -n ${NAMESPACE}

  # Waiting for pod to be restarted
  oc -n ${NAMESPACE} get pods -l app=quay
  ```

* Check whether the update is successful
  ```
  QUAY_APP_POD=$(oc -n ${NAMESPACE} get pods -l app=quay -o jsonpath='{.items[0].metadata.name}')
  oc -n ${NAMESPACE} rsh $QUAY_APP_POD cat /conf/stack/config.yaml
  ```

### Option: Collect repository log
* Creating an OAuth 2 [access token ](https://docs.redhat.com/en/documentation/red_hat_quay/3.15/html/red_hat_quay_api_guide/oauth2-access-tokens#creating-oauth-access-token)

* Collect repository log
  ```
  export TOKEN='dN4JWmQOrUeY4o16o0PIbBmKLrxma0NVjd82RRXK'
  export REGISTRY_URL='example-registry-quay-quay-enterprise.apps.ocp4.example.com'
  export ORGNAME=mirror
  export REPOSITORY=mirror-test
  
  curl -X GET \
    -H "Authorization: Bearer $TOKEN" \
    -H "Accept: application/json" \
    "https://${REGISTRY_URL}/api/v1/repository/${ORGNAME}/${REPOSITORY}/logs" |jq
  ```
