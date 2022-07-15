Oadp backup test

## 部署测试应用
**测试用 nginx pod**
~~~
$ oc new-project sample-backup
$ oc new-app --name nginx --docker-image quay.io/redhattraining/hello-world-nginx:v1.0
$ oc expose svc/nginx --hostname  nginx.apps.ocp4.example.net
$ curl nginx.apps.ocp4.example.net | grep Hello
<h1>Hello, world from nginx!</h1>

$ oc set volumes deployment/nginx \
   --add --name nginx-storage --type pvc --claim-class nfs-storage \
   --claim-mode RWO --claim-size 5Gi --mount-path /data \
   --claim-name nginx-storage

$ oc rsh nginx-5ffbd89cfd-wlbsw
sh-4.4$ df -h /data
Filesystem                                                                               Size  Used Avail Use% Mounted on
10.74.251.171:/nfs/sample-backup-nginx-storage-pvc-e7ddddef-8565-4f32-a9a3-5e4728dcff47  192G  127G   65G  67% /data
sh-4.4$ cat /data/test
hello
sh-4.4$ exit

$ oc get all -n sample-backup
NAME                         READY   STATUS    RESTARTS   AGE
pod/nginx-5ffbd89cfd-wlbsw   1/1     Running   0          53s

NAME            TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)    AGE
service/nginx   ClusterIP   172.30.228.52   <none>        8080/TCP   70s

NAME                    READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/nginx   1/1     1            1           70s

NAME                               DESIRED   CURRENT   READY   AGE
replicaset.apps/nginx-5b4bbd55     0         0         0       70s
replicaset.apps/nginx-5ffbd89cfd   1         1         1       53s
replicaset.apps/nginx-6fb64d848    0         0         0       69s

NAME                                   IMAGE REPOSITORY                                                                   TAGS   UPDATED
imagestream.image.openshift.io/nginx   default-route-openshift-image-registry.apps.ocp4.example.net/sample-backup/nginx   v1.0   About a minute ago

NAME                             HOST/PORT                     PATH   SERVICES   PORT       TERMINATION   WILDCARD
route.route.openshift.io/nginx   nginx.apps.ocp4.example.net          nginx      8080-tcp                 None

$ oc get pvc -n sample-backup
NAME            STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   AGE
nginx-storage   Bound    pvc-e7ddddef-8565-4f32-a9a3-5e4728dcff47   5Gi        RWO            nfs-storage    70s
~~~

## 安装环境
**安装 velero 客户端**
~~~
VERSION=v1.7.1
cd ~/ && curl -OL https://github.com/vmware-tanzu/velero/releases/download/${VERSION}/velero-${VERSION}-linux-amd64.tar.gz
tar -xvf velero-${VERSION}-linux-amd64.tar.gz
mv velero-${VERSION}-linux-amd64/velero /usr/local/bin/
~~~

**安装 MinIO**

a. 通过模板部署 MinIO s3 storage:
~~~
$ oc new-project minio
$ oc process -f https://raw.githubusercontent.com/liuxiaoyu-git/minio-ocp/master/minio.yaml | oc apply -n minio -f -
~~~

b.查看资源状态，并设置 MinIO Route 变量:
~~~
$ oc get pod -n minio
NAME             READY   STATUS      RESTARTS   AGE
minio-1-deploy   0/1     Completed   0          9m47s
minio-1-r4nns    1/1     Running     0          9m42s

$ MINIO_ADDR=$(oc get route minio -o jsonpath='https://{.spec.host}')
~~~

c.bastion 机器安装 Minio Client:
~~~
$ curl -OL https://dl.min.io/client/mc/release/linux-amd64/mc
$ chmod +x mc && mv mc /usr/bin
~~~

d.创建 Bucket:
~~~
- 设置访问 MinIO 服务的用户密码:
$ mc --insecure alias set my-minio ${MINIO_ADDR} minio minio123
mc: Configuration written to `/root/.mc/config.json`. Please update your access credentials.
mc: Successfully created `/root/.mc/share`.
mc: Initialized share uploads `/root/.mc/share/uploads.json` file.
mc: Initialized share downloads `/root/.mc/share/downloads.json` file.
Added `my-minio` successfully.

- 创建 Bucket,名称为 ocp-backup:
$ mc --insecure mb my-minio/ocp-backup
Bucket created successfully `my-minio/ocp-backup`.

- 确认 MinIO 中的 Bucket:
$ mc --insecure ls my-minio
[2022-01-07 09:29:26 UTC]     0B ocp-backup/
~~~

**安装minio-client**

a.在 minio-client 项目中云一个 Pod 作为运行 minio-client 的环境
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
~~~

b.进入部署好的名为 minio-client 的 Pod
~~~
$ oc -n minio-client rsh minio-client
~~~

c.在 minio-client 中安装 mc，并确认可以通过 http://minio.minio.svc 访问到前面部署的 MinIO 服务
~~~
/ # cd ~
~ # wget https://dl.min.io/client/mc/release/linux-amd64/mc
~ # chmod +x mc
~ # ./mc alias set my-minio http://minio.minio.svc minio minio123
mc: Configuration written to `/root/.mc/config.json`. Please update your access credentials.
mc: Successfully created `/root/.mc/share`.
mc: Initialized share uploads `/root/.mc/share/uploads.json` file.
mc: Initialized share downloads `/root/.mc/share/downloads.json` file.
Added `my-minio` successfully.
~ # ./mc ls my-minio/
[2022-01-07 13:02:41 UTC]     0B ocp-backup/
~~~

## 安装redhat-oadp-operator

a.webconsole -> Operators → OperatorHub -> OADP operator -> Install
~~~
$ oc get po -n openshift-adp
NAME                                                READY   STATUS    RESTARTS   AGE
openshift-adp-controller-manager-6f847bb84c-2smkc   1/1     Running   0          4h13m
~~~

b.在 openshift-adp 项目中创建名为 “cloud-credentials” 的 Secret，其中 Key 和 Value 参照以下内容
~~~
$ cat << EOF > /root/credentials-velero
[default]
aws_access_key_id=minio
aws_secret_access_key=minio123
EOF

$ oc create secret generic cloud-credentials -n openshift-adp --from-file cloud=/root/credentials-velero
~~~

c.根据以下 YAML 内容在 openshift-adp 项目中创建 DataProtectionApplication 对象
~~~
$ cat <<EOF > oadp-instance.yaml
apiVersion: oadp.openshift.io/v1alpha1
kind: DataProtectionApplication
metadata:
  name: oadp-minio
  namespace: openshift-adp
spec:
  backupLocations:
    - velero:
        config:
          profile: default
          region: minio
          s3ForcePathStyle: 'true'
          s3Url: 'http://minio.minio.svc/'
        credential:
          key: cloud
          name: cloud-credentials
        default: true
        objectStorage:
          bucket: ocp-backup
          prefix: velero
        provider: aws
  configuration:
    restic:
      enable: true
    velero:
      defaultPlugins:
        - openshift
        - aws
        - kubevirt
  snapshotLocations:
    - velero:
        config:
          profile: default
          region: minio
        provider: aws
EOF

$ oc create -f oadp-instance.yaml
~~~

d.查看 DataProtectionApplication 对象相关的 Resources
~~~
$ oc get po -n openshift-adp
NAME                                                READY   STATUS    RESTARTS   AGE
oadp-oadp-minio-1-aws-registry-745b5b86b8-l5zgr     1/1     Running   0          25s
openshift-adp-controller-manager-6f847bb84c-2smkc   1/1     Running   0          4h13m
restic-bl2m6                                        1/1     Running   0          24s
restic-cbx24                                        1/1     Running   0          24s
restic-zxz8v                                        1/1     Running   0          24s
velero-54cb6f7c8b-h5t8f                             1/1     Running   0          24s

$ oc get dataprotectionapplication -n openshift-adp
NAME         AGE
oadp-minio   2m46s
~~~

e.确认在 velero 已经有一个 BackupStorageLocation 对象了。根据名称可以知道，它是根据名为 oadp-minio 的 DataProtectionApplication 自动创建的
~~~
$ velero get backup-locations -n openshift-adp
NAME           PROVIDER   BUCKET/PREFIX       PHASE       LAST VALIDATED                  ACCESS MODE   DEFAULT
oadp-minio-1   aws        ocp-backup/velero   Available   2022-07-12 13:50:24 +0000 UTC   ReadWrite     true
~~~

## 对应用进行备份和恢复

**备份应用**

a. 针对 sample-backup 项目创建一个名为 nginx-sample-backup 的 backup
~~~
- 无volumes的时候使用如下方法创建backup:
$ velero backup create nginx-sample-backup --include-namespaces sample-backup -n openshift-adp
Backup request "nginx-sample-backup" submitted successfully.
Run `velero backup describe nginx-sample-backup` or `velero backup logs nginx-sample-backup` for more details.

- 有volumes的时候使用如下方法创建backup:
$ cat << EOF | oc apply -f -
apiVersion: velero.io/v1
kind: Backup
metadata:
  name: nginx-sample-backup
  namespace: openshift-adp
spec:
    hooks: {}
    includedNamespaces:
    - sample-backup
    storageLocation: oadp-minio-1
    defaultVolumesToRestic: true 
    ttl: 720h0m0s
EOF
~~~

b.查看 Velero 的 Backup 对象，直到 STATUS 为 Completed。
~~~
$ velero get backup -n openshift-adp
NAME                  STATUS      ERRORS   WARNINGS   CREATED                         EXPIRES   STORAGE LOCATION   SELECTOR
nginx-sample-backup   Completed   0        0          2022-07-12 14:12:30 +0000 UTC   29d       oadp-minio-1       <none>
~~~

c.确认 “my-minio/ocp-backup/velero/backups/nginx-sample-backup” 是否有备份数据
~~~
$ mc ls my-minio/ocp-backup/velero/backups/nginx-sample-backup
[2022-07-12 14:12:56 UTC]    29B STANDARD nginx-sample-backup-csi-volumesnapshotcontents.json.gz
[2022-07-12 14:12:56 UTC]    29B STANDARD nginx-sample-backup-csi-volumesnapshots.json.gz
[2022-07-12 14:12:56 UTC]  11KiB STANDARD nginx-sample-backup-logs.gz
[2022-07-12 14:12:56 UTC]   891B STANDARD nginx-sample-backup-podvolumebackups.json.gz
[2022-07-12 14:12:56 UTC]   948B STANDARD nginx-sample-backup-resource-list.json.gz
[2022-07-12 14:12:56 UTC]    29B STANDARD nginx-sample-backup-volumesnapshots.json.gz
[2022-07-12 14:12:56 UTC] 176KiB STANDARD nginx-sample-backup.tar.gz
[2022-07-12 14:12:56 UTC] 2.6KiB STANDARD velero-backup.json
~~~

**恢复应用**

a.删除 sample-backup 测试应用的项目模拟灾难
~~~
$ oc delete project sample-backup
~~~

b.使用名为 nginx-sample-backup 的备份创一个建名为 nginx-sample-restore 的 restore
~~~
- 无volumes的时候使用如下方法创建restore:
$ velero create restore nginx-sample-restore --from-backup nginx-sample-backup -n openshift-adp
Restore request "nginx-sample-restore" submitted successfully.
Run `velero restore describe nginx-sample-restore` or `velero restore logs nginx-sample-restore` for more details.

- 有volumes的时候使用如下方法创建restore:
$ cat << EOF | oc apply -f -
apiVersion: velero.io/v1
kind: Restore
metadata:
  name: nginx-sample-restore
  namespace: openshift-adp
spec:
  backupName: nginx-sample-backup
  restorePVs: true
EOF
~~~

e.查看 velero 的 Restore 对象，直到 STATUS 为 Completed
~~~
$ velero get restore -n openshift-adp
NAME                   BACKUP                STATUS      STARTED                         COMPLETED                       ERRORS   WARNINGS   CREATED                         SELECTOR
nginx-sample-restore   nginx-sample-backup   Completed   2022-07-12 14:16:14 +0000 UTC   2022-07-12 14:16:41 +0000 UTC   0        4          2022-07-12 14:16:14 +0000 UTC   <none>
~~~

f. 确认 nginx-app 项目和其中的资源又被恢复了
~~~
$ oc get all -n sample-backup
NAME                         READY   STATUS    RESTARTS   AGE
pod/nginx-5ffbd89cfd-wlbsw   1/1     Running   0          90s

NAME            TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)    AGE
service/nginx   ClusterIP   172.30.21.198   <none>        8080/TCP   88s

NAME                    READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/nginx   1/1     1            1           89s

NAME                               DESIRED   CURRENT   READY   AGE
replicaset.apps/nginx-5ffbd89cfd   1         1         1       89s

NAME                                   IMAGE REPOSITORY                                                                   TAGS   UPDATED
imagestream.image.openshift.io/nginx   default-route-openshift-image-registry.apps.ocp4.example.net/sample-backup/nginx   v1.0   About a minute ago

NAME                             HOST/PORT                     PATH   SERVICES   PORT       TERMINATION   WILDCARD
route.route.openshift.io/nginx   nginx.apps.ocp4.example.net          nginx      8080-tcp                 None

$ oc get pvc -n sample-backup
NAME            STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   AGE
nginx-storage   Bound    pvc-088935bc-a85f-402b-b3fe-ddf449f60dd1   5Gi        RWO            nfs-storage    2m4s

$ oc -n sample-backup rsh nginx-5ffbd89cfd-wlbsw  
Defaulted container "nginx" out of: nginx, restic-wait (init)
sh-4.4$ df -h /data
Filesystem                                                                               Size  Used Avail Use% Mounted on
10.74.251.171:/nfs/sample-backup-nginx-storage-pvc-088935bc-a85f-402b-b3fe-ddf449f60dd1  192G  127G   65G  67% /data
sh-4.4$ cat /data/test 
hello
sh-4.4$ exit
~~~

## 定时备份
~~~
- 无volumes的时候使用如下方法创建定时计划备份
$ velero create schedule nginx-sample-backup-schedule --schedule="0 7 * * *" --include-namespaces sample-backup

- 有volumes的时候使用如下方法创建定时计划备份
$ cat << EOF | oc apply -f -
apiVersion: velero.io/v1
kind: Schedule
metadata:
  name: nginx-sample-backup-schedule
  namespace: openshift-adp
spec:
  schedule: 0 7 * * * 
  template:
    hooks: {}
    includedNamespaces:
    - sample-backup
    storageLocation: oadp-minio-1
    defaultVolumesToRestic: true 
    ttl: 720h0m0s
EOF
~~~
