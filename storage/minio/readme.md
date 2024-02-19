## Deploy Minio Object Storage

### Install Minio according to different options

#### Options A: Deploying a Minio Pod with ephemeral volume

* EmptyDir is a temporary storage volume used to provide transient storage space during the lifetime of a Pod.  

  ```
  export NAMESPACE="minio"
  curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/storage/minio/deploy-minio-with-ephemeral-volume.yaml | envsubst | oc apply -f -
  
  oc get pod,route -n ${NAMESPACE}
  ```

#### Options B: Deploying Minio with Local volume as the Backend Storage

* First specify the worker node where Minio pv/pod is located, and then create the local volume and Minio.

  ```
  export NAMESPACE="minio"
  export PV_NODE_NAME="worker01.ocp4.example.com"
  export STORAGE_SIZE="50Gi"
  ssh core@${PV_NODE_NAME} sudo mkdir -p -m 777 /mnt/minio-data

  curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/storage/minio/deploy-minio-with-local-storage.yaml | envsubst | oc apply -f -

  oc get pod,route,pvc -n ${NAMESPACE}
  ```

#### Options C: Deploying Minio with NFS StorageClass as the Backend Storage

* Deploy [NFS StorageClass](https://github.com/pancongliang/openshift/blob/main/storage/nfs-storageclass/readme.md), if storage class has been deployed,only need to set the variables.

* Deploy Minio Object Storage

  ```
  export NAMESPACE="minio"
  export STORAGE_CLASS_NAME="managed-nfs-storage"
  export STORAGE_SIZE="50Gi"
  curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/storage/minio/deploy-minio-with-persistent-volume.yaml | envsubst | oc apply -f -

  oc get pod,route,pvc -n ${NAMESPACE}
  ```

### Install the Minio client

* Minio Client (mc) is a command line tool for managing and operating Minio object storage services.

  ```
  curl -OL https://dl.min.io/client/mc/release/linux-amd64/mc

  chmod +x mc && mv mc /usr/bin/
  ```

### Access Minio and create bucket

* Create a bucket by accessing the Minio Console (Default ID/PW: minioadmin)
 
  ```
  oc get route minio-console -n ${NAMESPACE} -o jsonpath='http://{.spec.host}{"\n"}'
  ```

* Create bucket through Minio Client (Default ID/PW: minioadmin)
  
  Create an alias named "my-minio" and Access Minio, After creating/using an "alias", the Minio url can be ignored the next time visit.
  ```    
  export MINIO_ADDR=$(oc get route minio -n ${NAMESPACE} -o jsonpath='http://{.spec.host}')
  
  mc alias set my-minio ${MINIO_ADDR} minioadmin minioadmin
  ``` 
  Create a bucket named "loki-bucket" in the "my-minio" alias
  ```
  export BUCKET_NAME="loki-bucket"   # loki bucket
  export BUCKET_NAME="quay-bucket"   # quay bucket
  export BUCKET_NAME="oadp-bucket"   # oadp bucket
  export BUCKET_NAME="mtc-bucket"    # mtc bucket
  
  mc mb my-minio/${BUCKET_NAME}
  ```
  Commonly used [mc commands](https://min.io/docs/minio/linux/reference/minio-mc.html?ref=docs#command-quick-reference)
  ```
  # List "my-minio" alias info
  mc alias list my-minio

  # List buckets in "my-minio" alias
  mc ls my-minio

  # List files in bucket
  mc ls my-minio/${BUCKET_NAME}

  # Delete  bucket
  mc rb --force my-minio/loki-bucket
  ```  
