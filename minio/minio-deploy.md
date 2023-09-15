
**1. Create minio project**
~~~
$ oc new-project minio
~~~

**2. Create minio resource**

Options 1. Create a minio that uses ephemeral data.
~~~
$ oc process -f https://raw.githubusercontent.com/pancongliang/OpenShift/main/minio/minio-ephemeral.yaml | oc apply -n minio -f -
~~~

Options 2. Create a minio that uses persistent data.
~~~
# Create pv
$ cat << EOF | oc apply -f -
apiVersion: v1
kind: PersistentVolume
metadata:
  name: minio-pv
  labels:
    name: minio-pv
spec:
  capacity:
    storage: 100Gi
  accessModes:      
  - ReadWriteMany
  persistentVolumeReclaimPolicy: Retain
  nfs:
    path: /nfs/minio-pv
    server: 10.74.251.171
EOF

# Create pvc
$ cat << EOF | oc apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: minio-pvc
spec:
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 100Gi
  selector:
    matchLabels:
      name: minio-pv
EOF

$ oc process -f https://raw.githubusercontent.com/pancongliang/OpenShift/main/minio/minio-persistent.yaml | oc apply -n minio -f -
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
