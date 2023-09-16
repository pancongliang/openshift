### Deploy minio 

#### Options A: Deploy a minio that uses ephemeral data
~~~
$ oc new-project minio
$ oc create -f https://raw.githubusercontent.com/pancongliang/openshift/main/storage/minio/minio_ephemeral.yaml

$ oc get pod -n minio
NAME                     READY   STATUS    RESTARTS   AGE
minio-56f884d55d-l8pmh   1/1     Running   0          10s
~~~

#### Options B: Deploy a minio that uses persistent data

* Install nfs storageclass
~~~
# Setting parameters
$ export NFS_NAMESPACE="nfs-client-provisioner"
$ export NFS_SERVER_IP="10.74.251.171"
$ export NFS_DIR="/nfs"

# Skip if nfs rpm is already installed
$ wget https://raw.githubusercontent.com/pancongliang/openshift/main/storage/nfs_storageclass/01_install_nfs_package.sh
$ source 01_install_nfs_package.sh

# Deploy nfs storageclass
$ wget https://raw.githubusercontent.com/pancongliang/openshift/main/storage/nfs_storageclass/02_deploy_nfs_storageclass.sh
$ source 02_deploy_nfs_storageclass.sh
~~~

* Deploy a minio that uses persistent data
~~~
# If there is already a storageclass, skip this step and then modify the pvc information in the minio_persistent.yaml file
$ oc new-project minio
$ oc create -f https://raw.githubusercontent.com/pancongliang/openshift/main/storage/minio/minio_persistent.yaml
$ oc get pod -n minio
~~~

### Install the Minio client
~~~
$ curl -OL https://dl.min.io/client/mc/release/linux-amd64/mc
$ chmod +x mc && mv mc /usr/bin/
~~~

### Access minio and create bucket
~~~
# Access minio-console(Default ID/PW: minioadmin)
$ oc get route minio-console -n minio -o jsonpath='http://{.spec.host}'

# Access minio-cli(Default ID/PW: minioadmin)
$ MINIO_ADDR=$(oc get route minio -n minio -o jsonpath='http://{.spec.host}')

# Create an alias named "my-minio"
$ mc --insecure alias set my-minio ${MINIO_ADDR} minioadmin minioadmin

# Create a bucket named "loki-bucket-minio" in the "my-minio" alias
$ mc --insecure mb my-minio/loki-bucket-minio
Bucket created successfully `my-minio/loki-bucket-minio`.

# List "my-minio" alias info
$ mc alias list my-minio
my-minio
  URL       : http://minio-minio.apps.ocp4.example.com
  AccessKey : minioadmin
  SecretKey : minioadmin

# List buckets in "my-minio" alias
$ mc --insecure ls my-minio
[2022-01-07 09:29:26 UTC]     0B loki-bucket-minio/

# Command Quick Reference: https://min.io/docs/minio/linux/reference/minio-mc.html?ref=docs#command-quick-reference
~~~
