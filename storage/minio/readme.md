### Deploy Minio Object Storage

#### Options A: Deploying a Minio Pod with ephemeral volume

* EmptyDir is a temporary storage volume used to provide transient storage space during the lifetime of a Pod.  

  ```
  export NAMESPACE="minio"
  
  curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/storage/minio/deploy_minio_with_ephemeral_volume.yaml | envsubst | oc apply -f -

  oc get pod,route -n ${NAMESPACE}
  ```

#### Options B: Deploying Minio with Local volume as the Backend Storage

* First specify the worker node where Minio pv/pod is located, and then create the local volume and Minio.

  ```
  export NAMESPACE="minio"
  export PV_NODE_NAME="worker01.ocp4.example.com"

  ssh core@${PV_NODE_NAME} sudo mkdir -p -m 777 /mnt/minio-data

  curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/storage/minio/deploy_minio_with_local_storage.yaml | envsubst | oc apply -f -

  oc get pod,route,pvc -n ${NAMESPACE}
  ```

#### Options C: Deploying Minio with NFS StorageClass as the Backend Storage

* Deploy NFS StorageClass, if storage class or pv has been deployed,only need to set the variables.

  Set variables
  ```
  export NAMESPACE="nfs-client-provisioner"
  export NFS_SERVER_IP="10.74.251.171"
  export NFS_DIR="/nfs"
  ```
  Install and configure NFS server, skip if already installed
  ```
  wget https://raw.githubusercontent.com/pancongliang/openshift/main/storage/nfs_storageclass/01_install_nfs_package.sh

  source 01_install_nfs_package.sh
  ```
  Deploy NFS StorageClass
  ```
  curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/storage/nfs_storageclass/02_deploy_nfs_storageclass.yaml | envsubst | oc apply -f -
  ```

* Deploy Minio Object Storage
  
  If there is already a storage class or pv, can directly modify the pvc content in the following yaml file.
  ```
  export NAMESPACE="minio"

  curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/storage/minio/deploy_minio_with_persistent_volume.yaml | envsubst | oc apply -f -

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
  oc get route minio-console -n minio -o jsonpath='http://{.spec.host}'
  ```

* Create bucket through Minio Client (Default ID/PW: minioadmin)
  
  Create an alias named "my-minio" and Access Minio, After creating/using an "alias", the Minio url can be ignored the next time visit.
  ```    
  MINIO_ADDR=$(oc get route minio -n minio -o jsonpath='http://{.spec.host}')
  
  mc alias set my-minio ${MINIO_ADDR} minioadmin minioadmin
  ``` 
  Create a bucket named "loki-bucket-minio" in the "my-minio" alias
  ```
  BUCKET_NAME="loki-bucket-minio"
  
  mc mb my-minio/${BUCKET_NAME}
  ```
  Commonly used [mc commands](https://min.io/docs/minio/linux/reference/minio-mc.html?ref=docs#command-quick-reference)
  ```
  # List "my-minio" alias info
  mc alias list my-minio

  # List buckets in "my-minio" alias
  mc ls my-minio

  # Delete  bucket
  mc rb --force my-minio/loki-bucket-minio
  ```  
