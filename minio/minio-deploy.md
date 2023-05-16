
**1.Create minio project**
~~~
$ oc new-project minio
~~~

**2.Create minio resource**

Optional(a). ephemeral data.
~~~
$ oc process -f https://raw.githubusercontent.com/liuxiaoyu-git/minio-ocp/master/minio.yaml | oc apply -n minio -f -
~~~

Optional(b). persistent data.
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

# Create pvc(pvc name is specified as minio-data)
$ cat << EOF | oc apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: minio-data
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


**3.Check the status of deployed resources and confirm the Route address**
~~~
$ oc get pod -n minio
NAME             READY   STATUS      RESTARTS   AGE
minio-1-deploy   0/1     Completed   0          9m47s
minio-1-r4nns    1/1     Running     0          9m42s
$ MINIO_ADDR=$(oc get route minio -n minio -o jsonpath='https://{.spec.host}')
~~~

**4.Install the Minio client**

Optional(a). Install the Minio client on the basion machine and use the route address to access.
~~~
$ curl -OL https://dl.min.io/client/mc/release/linux-amd64/mc
$ chmod +x mc && mv mc /usr/bin
~~~

Optional(b). Install the Minio client in the pod and use the service address to access.
~~~
$ oc new-project minio-client
$ oc apply -f - << EOF
apiVersion: v1
kind: Pod
metadata:
  name: minio-client
  namespace: minio-client
spec:
  containers:
    - name: minio-client
      image: busybox
      command: [ "/bin/sh", "-c", "while true ; do date; sleep 1; done;" ]
  restartPolicy: Never
EOF

$ oc get po -n minio-client
NAME           READY   STATUS    RESTARTS   AGE
minio-client   1/1     Running   0          98s

$ oc -n minio-client rsh minio-client
/ # cd ~
~ # wget https://dl.min.io/client/mc/release/linux-amd64/mc
~ # chmod +x mc
~~~

**5.Access Minio and create bucket**

a.Access Minio(Default account password: minio/minio123)
~~~
# Use the route address in the bastion machine to access minio
$ mc --insecure alias set my-minio ${MINIO_ADDR} minio minio123

# Use the servive address in pod to access minio(Default account password: minio/minio123)
$ mc --insecure alias set my-minio ${MINIO_ADDR} minio minio123
~~~

b.Create bucket.
~~~
# Create bucket
$ mc --insecure mb my-minio/ocp-bucket
Bucket created successfully `my-minio/ocp-bucket`.

# Confirm that the bucket is created successfully
$ mc --insecure ls my-minio
[2022-01-07 09:29:26 UTC]     0B ocp-bucket/
~~~

**Common MinIO commands**
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
