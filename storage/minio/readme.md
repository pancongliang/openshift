### Deploy MinIO Object Storage

#### Options A: Deploying a MinIO Pod with ephemeral volume

* emptyDir is a temporary storage volume used to provide transient storage space during the lifetime of a Pod.  

  ~~~
  $ oc new-project minio   # Custom namespace
  $ oc create -f https://raw.githubusercontent.com/pancongliang/openshift/main/storage/minio/deploy_minio_with_ephemeral_volume.yaml
  $ oc get pod,route -n minio
  ~~~

#### Options B: Deploying MinIO with NFS StorageClass as the Backend Storage

* Deploy NFS StorageClass, if storage class or pv has been deployed,only need to set the `variables`.

  Set variables
  ~~~
  $ export NFS_NAMESPACE="nfs-client-provisioner"
  $ export NFS_SERVER_IP="10.74.251.171"
  $ export NFS_DIR="/nfs"
  ~~~
  Install and configure NFS server, skip if already installed
  ~~~
  $ wget https://raw.githubusercontent.com/pancongliang/openshift/main/storage/nfs_storageclass/01_install_nfs_package.sh
  $ source 01_install_nfs_package.sh
  ~~~
  Deploy NFS StorageClass
  ~~~
  $ wget https://raw.githubusercontent.com/pancongliang/openshift/main/storage/nfs_storageclass/02_deploy_nfs_storageclass.sh
  $ source 02_deploy_nfs_storageclass.sh
  ~~~

* Deploy MinIO Object Storage
  
  If there is already a storage class or pv, can directly modify the pvc content in the following yaml file.
  ~~~
  $ oc new-project minio   # Custom namespace
  $ oc create -f https://raw.githubusercontent.com/pancongliang/openshift/main/storage/minio/deploy_minio_with_persistent_volume.yaml
  $ oc get pod -n minio
  ~~~

### Install the MinIO client

* Minio Client (mc) is a command line tool for managing and operating Minio object storage services.

  ~~~
  $ curl -OL https://dl.min.io/client/mc/release/linux-amd64/mc
  $ chmod +x mc && mv mc /usr/bin/
  ~~~

### Access MinIO and create bucket

* Create a bucket by accessing the MinIO Console (Default ID/PW: minioadmin)
 
  ~~~
  $ oc get route minio-console -n minio -o jsonpath='http://{.spec.host}'
  ~~~

* Create bucket through Minio Client (Default ID/PW: minioadmin)
  
  Create an alias named "my-minio"
  ~~~    
  $ MINIO_ADDR=$(oc get route minio -n minio -o jsonpath='http://{.spec.host}')
  $ mc --insecure alias set my-minio ${MINIO_ADDR} minioadmin minioadmin
  ~~~ 
  Create a bucket named "loki-bucket-minio" in the "my-minio" alias
  ~~~
  $ BUCKET_NAME="loki-bucket-minio"
  $ mc --insecure mb my-minio/${BUCKET_NAME}
  Bucket created successfully `my-minio/loki-bucket-minio`.
  ~~~
  Commonly used [mc commands](https://min.io/docs/minio/linux/reference/minio-mc.html?ref=docs#command-quick-reference)
  ~~~
  # List "my-minio" alias info
  $ mc alias list my-minio
  my-minio
    URL       : http://minio-minio.apps.ocp4.example.com
    AccessKey : minioadmin
    SecretKey : minioadmin

  # List buckets in "my-minio" alias
  $ mc --insecure ls my-minio
  [2022-01-07 09:29:26 UTC]     0B loki-bucket-minio/

  # Delete  bucket
  $ mc rb --force my-minio/loki-bucket-minio
  ~~~  
