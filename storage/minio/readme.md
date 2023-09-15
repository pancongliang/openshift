**1. Create minio resource**

Options a. Create a minio that uses ephemeral data.
~~~
$ export MINIO_NAMESPACE="minio"
$ envsubst < https://raw.githubusercontent.com/pancongliang/openshift/main/storage/minio/minio_ephemeral.yaml | oc create -f -
~~~

Options b. Create a minio that uses persistent data.
~~~
# Install nfs storageclass
$ export NFS_NAMESPACE="nfs-client-provisioner"
$ export NFS_SERVER_IP="10.74.251.171"
$ export NFS_DIR="/nfs"

$ wget https://raw.githubusercontent.com/pancongliang/openshift/main/storage/nfs_storageclass/01_install_nfs_package.sh
$ wget https://raw.githubusercontent.com/pancongliang/openshift/main/storage/nfs_storageclass/02_create_nfs_sc.sh
$ source 01_install_nfs_package.sh
$ source 02_create_nfs_sc.sh

# Create minio
$ exaport MINIO_NAMESPACE="minio"
$ envsubst < https://raw.githubusercontent.com/pancongliang/openshift/main/storage/minio/minio_persistent.yaml | oc create -f -
~~~

**2. Check the status of deployed resources**
~~~
$ oc get pod -n minio
NAME                    READY   STATUS    RESTARTS   AGE
minio-86b46b44c-bm4js   1/1     Running   0          1m
~~~

**3. Install the Minio client**
~~~
$ curl -OL https://dl.min.io/client/mc/release/linux-amd64/mc
$ chmod +x mc && mv mc /usr/local/bin/
~~~

**4. Access minio and create bucket**
~~~
# Access minio-console(Default ID/PW: minioadmin)
$ MINIO_ADDR=$(oc get route minio-console -n minio -o jsonpath='http://{.spec.host}')

# Access minio-cli(Default ID/PW: minioadmin)
$ MINIO_ADDR=$(oc get route minio -n minio -o jsonpath='http://{.spec.host}')

# Create an alias named "my-minio"
$ mc --insecure alias set my-minio ${MINIO_ADDR} minioadmin minioadmin

# Create a bucket named "loki-bucket" in the "my-minio" alias
$ mc --insecure mb my-minio/loki-bucket
Bucket created successfully `my-minio/loki-bucket`.

# List "my-minio" alias info
$ mc alias list my-minio
my-minio
  URL       : http://minio-minio.apps.ocp4.example.com
  AccessKey : minioadmin
  SecretKey : minioadmin

# List buckets in "my-minio" alias
$ mc --insecure ls my-minio
[2022-01-07 09:29:26 UTC]     0B loki-bucket/

# Create the following secret when an application uses minio
$ cat << EOF | oc apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: access-minio
stringData:
  access_key_id: minioadmin
  access_key_secret: minioadmin
  bucketnames: loki-bucket
  endpoint: http://minio-minio.apps.ocp4.example.com
  region: minio
EOF
~~~
