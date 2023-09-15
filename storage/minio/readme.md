**2. Create minio resource**

Options 1. Create a minio that uses ephemeral data.
~~~
$ export MINIO_NAMESPACE="minio"
$ envsubst < https://raw.githubusercontent.com/pancongliang/openshift/main/storage/minio/minio_ephemeral.yaml | oc create -f -
~~~

Options 2. Create a minio that uses persistent data.
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

**3. Check the status of deployed resources**
~~~
$ oc get pod -n minio
NAME             READY   STATUS      RESTARTS   AGE
minio-1-deploy   0/1     Completed   0          9m47s
minio-1-r4nns    1/1     Running     0          9m42s
~~~

**4. Install the Minio client**
~~~
$ curl -OL https://dl.min.io/client/mc/release/linux-amd64/mc
$ chmod +x mc && mv mc /usr/bin
~~~

**5. Access minio and create bucket**
~~~
# Access minio
$ MINIO_ADDR=$(oc get route minio -n minio -o jsonpath='https://{.spec.host}')
$ mc --insecure alias set my-minio ${MINIO_ADDR} minio minio123

# Create bucket
$ mc --insecure mb my-minio/loki-bucket
Bucket created successfully `my-minio/loki-bucket`.

# Confirm bucket
$ mc --insecure ls my-minio
[2022-01-07 09:29:26 UTC]     0B loki-bucket/
~~~

**6. Access minio from the cluster internal**
~~~
$ cat << EOF | oc apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: access-minio
stringData:
  access_key_id: minio
  access_key_secret: minio123
  bucketnames: loki-bucket
  endpoint: http://minio.minio.svc
  region: minio
EOF
~~~

**Minio commands**
~~~
- View MinIO configuration
$ mc alias ls my-minio
my-minio
  URL       : https://minio-minio.apps.ocp4.example.com
  AccessKey : minio
  SecretKey : minio123
  API       : s3v4
  Path      : auto

- Copy files between buckets
$ echo hello minio > hello
$ mc --insecure cp hello my-minio/${MY_BUCKET}/test/hellominio
hello:                        12 B / 12 B ┃▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓┃ 50 B/s 0s
$ mc --insecure ls my-minio/${MY_BUCKET}/test/
[2022-01-07 08:17:10 UTC]    12B hellominio
$ mc --insecure cat my-minio/${MY_BUCKET}/test/hellominio
hello minio

- Delete Bucket
$ mc --insecure rm --recursive --force my-minio/${MY_BUCKET}/
Removing `my-minio/hello`.
Removing `my-minio/test/hellominio`.
~~~
