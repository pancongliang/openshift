## Deploy Minio Object Storage

### Install Minio according to different options

#### Options A: Deploying a Minio Pod with ephemeral volume

* EmptyDir is a temporary storage volume used to provide transient storage space during the lifetime of a Pod.  

  ```
  curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/storage/minio/deploy-minio-with-ephemeral-volume.yaml | envsubst | oc apply -f -
  
  oc get pod,route -n minio
  ```

#### Options B: Deploying Minio with Local volume as the Backend Storage

* First specify the worker node where Minio pv/pod is located, and then create the local volume and Minio.

  ```
  export PV_NODE_NAME="worker01.ocp4.example.com"
  export STORAGE_SIZE="50Gi"
  ssh core@${PV_NODE_NAME} sudo mkdir -p -m 777 /mnt/minio-data

  curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/storage/minio/deploy-minio-with-local-storage.yaml | envsubst | oc apply -f -

  oc get pod,route,pvc -n minio
  ```

#### Options C: Deploying Minio with NFS StorageClass as the Backend Storage

* Deploy [NFS StorageClass](https://github.com/pancongliang/openshift/blob/main/storage/nfs-sc/readme.md), Can be skipped if a default storage class exists.

* Deploy Minio Object Storage

  ```
  export STORAGE_SIZE="50Gi"
  curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/storage/minio/deploy-minio-with-persistent-volume.yaml | envsubst | oc apply -f -

  oc get pod,route,pvc -n minio
  ```

### Access Minio and create bucket

* Create a bucket by accessing the Minio Console (Default ID/PW: minioadmin)
 
  ```
  oc get route minio-console -n minio -o jsonpath='http://{.spec.host}{"\n"}'
  ```

* Create bucket through Minio Client (Default ID/PW: minioadmin)
  
  Create an alias named "my-minio" and Access Minio, After creating/using an "alias", the Minio url can be ignored the next time visit
  ```    
  export BUCKET_HOST=$(oc get route minio -n minio -o jsonpath='http://{.spec.host}')
  
  oc rsh -n minio deployments/minio mc alias set my-minio ${BUCKET_HOST} minioadmin minioadmin
  ```

  Create a bucket named "loki-bucket, quay-bucket, oadp-bucket, mtc-bucket" in the "my-minio" alias
  ```
  for BUCKET_NAME in "loki-bucket" "quay-bucket" "oadp-bucket" "mtc-bucket"; do
    oc rsh -n minio deployments/minio mc mb my-minio/$BUCKET_NAME
  done
  ```

  Commonly used [mc commands](https://min.io/docs/minio/linux/reference/minio-mc.html?ref=docs#command-quick-reference)
  ```
  # List "my-minio" alias info
  oc rsh -n minio deployments/minio mc alias list my-minio

  # List buckets in "my-minio" alias
  oc rsh -n minio deployments/minio mc ls my-minio

  # List files in bucket
  oc rsh -n minio deployments/minio mc ls my-minio/${BUCKET_NAME}

  # Delete  bucket
  oc rsh -n minio deployments/minio mc rb --force my-minio/loki-bucket
  ```  
