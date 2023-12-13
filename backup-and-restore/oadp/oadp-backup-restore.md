##  OADP Application backup and restore

### Deploy test application
* nginx pod for testing
  ```
  oc new-project sample-backup
  oc new-app --name nginx --docker-image quay.io/redhattraining/hello-world-nginx:v1.0
  oc expose svc/nginx --hostname  nginx.apps.ocp4.example.net
  curl nginx.apps.ocp4.example.net | grep Hello
  <h1>Hello, world from nginx!</h1>
  
  oc set volumes deployment/nginx \
    --add --name nginx-storage --type pvc --claim-class nfs-storage \
    --claim-mode RWO --claim-size 5Gi --mount-path /data \
    --claim-name nginx-storage
  
  oc rsh nginx-5ffbd89cfd-wlbsw
  sh-4.4$ df -h /data
  Filesystem                                                                               Size  Used Avail Use% Mounted on
  10.74.251.171:/nfs/sample-backup-nginx-storage-pvc-e7ddddef-8565-4f32-a9a3-5e4728dcff47  192G  127G   65G  67% /data
  sh-4.4$ cat /data/test
  hello
  sh-4.4$ exit
  
  oc get all -n sample-backup
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
  
  oc get pvc -n sample-backup
  NAME            STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   AGE
  nginx-storage   Bound    pvc-e7ddddef-8565-4f32-a9a3-5e4728dcff47   5Gi        RWO            nfs-storage    70s
  ```

### Install dependent components
* Install velero client on bastion machine
  ```
  VERSION=v1.7.1
  cd ~/ && curl -OL https://github.com/vmware-tanzu/velero/releases/download/${VERSION}/velero-${VERSION}-linux-amd64.tar.gz
  tar -xvf velero-${VERSION}-linux-amd64.tar.gz
  mv velero-${VERSION}-linux-amd64/velero /usr/local/bin/
  ```

* Deploy Minio Object Storage
  [Create `oadp-bucket`](Create `oadp-bucket` after Deploy Minio Object Storage) after [Deploy Minio](https://github.com/pancongliang/openshift/blob/main/storage/minio/readme.md#deploy-minio-object-storage) Object Storage

### Install and configure OADP Operator

* webconsole -> Operators → OperatorHub -> OADP operator -> Install
  ```
  oc get po -n openshift-adp
  NAME                                                READY   STATUS    RESTARTS   AGE
  openshift-adp-controller-manager-6f847bb84c-2smkc   1/1     Running   0          4h13m
  ```

* Create a Secret named "cloud-credentials" in the openshift-adp project to allow access to Minio
  ```
  cat << EOF > /root/credentials-velero
  [default]
  aws_access_key_id=minioadmin
  aws_secret_access_key=minioadmin
  EOF

  oc create secret generic cloud-credentials -n openshift-adp --from-file cloud=/root/credentials-velero
  ```

* Create DataProtectionApplication
  ```
  cat <<EOF | oc apply -f -
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
  ```

* View the Resources related to the DataProtectionApplication object
  ```
  oc get po -n openshift-adp
  NAME                                                READY   STATUS    RESTARTS   AGE
  oadp-oadp-minio-1-aws-registry-745b5b86b8-l5zgr     1/1     Running   0          25s
  openshift-adp-controller-manager-6f847bb84c-2smkc   1/1     Running   0          4h13m
  restic-bl2m6                                        1/1     Running   0          24s
  restic-cbx24                                        1/1     Running   0          24s
  restic-zxz8v                                        1/1     Running   0          24s
  velero-54cb6f7c8b-h5t8f                             1/1     Running   0          24s

  oc get dataprotectionapplication -n openshift-adp
  NAME         AGE
  oadp-minio   2m46s

  velero get backup-locations -n openshift-adp
  NAME           PROVIDER   BUCKET/PREFIX       PHASE       LAST VALIDATED                  ACCESS MODE   DEFAULT
  oadp-minio-1   aws        oadp-backet/velero   Available   2022-07-12 13:50:24 +0000 UTC   ReadWrite     true
  ```

### Backing up applications

* Create a Backup CR
  ```
  cat << EOF | oc apply -f -
  apiVersion: velero.io/v1
  kind: Backup
  metadata:
    name: nginx-sample-backup
    namespace: openshift-adp
  spec:
      hooks: {}
      includedNamespaces:
      - sample-backup                 # Specify the namespace name of the backup object
      storageLocation: oadp-minio-1   # Based on the name output by <velero get backup-locations -n openshift-adp>
      defaultVolumesToRestic: true 
      ttl: 720h0m0s
  EOF
  ```

* Verify that the status of the Backup CR is Completed:
  ```
  velero get backup -n openshift-adp
  NAME                  STATUS      ERRORS   WARNINGS   CREATED                         EXPIRES   STORAGE LOCATION   SELECTOR
  nginx-sample-backup   Completed   0        0          2022-07-12 14:12:30 +0000 UTC   29d       oadp-minio-1       <none>

  oc get backup -n openshift-adp nginx-sample-backup -o jsonpath='{.status.phase}'
  ```

* 确认 “my-minio/ocp-backup/velero/backups/nginx-sample-backup” 是否有备份数据
  ```
  mc ls my-minio/oadp-backet/velero/backups/nginx-sample-backup
  [2022-07-12 14:12:56 UTC]    29B STANDARD nginx-sample-backup-csi-volumesnapshotcontents.json.gz
  [2022-07-12 14:12:56 UTC]    29B STANDARD nginx-sample-backup-csi-volumesnapshots.json.gz
  [2022-07-12 14:12:56 UTC]  11KiB STANDARD nginx-sample-backup-logs.gz
  [2022-07-12 14:12:56 UTC]   891B STANDARD nginx-sample-backup-podvolumebackups.json.gz
  [2022-07-12 14:12:56 UTC]   948B STANDARD nginx-sample-backup-resource-list.json.gz
  [2022-07-12 14:12:56 UTC]    29B STANDARD nginx-sample-backup-volumesnapshots.json.gz
  [2022-07-12 14:12:56 UTC] 176KiB STANDARD nginx-sample-backup.tar.gz
  [2022-07-12 14:12:56 UTC] 2.6KiB STANDARD velero-backup.json
  ```

###  Restoring applications
* Delete the namespace to back up the object
  ```
  oc delete project sample-backup
  ```

* Creating a Restore CR
  ```
  cat << EOF | oc apply -f -
  apiVersion: velero.io/v1
  kind: Restore
  metadata:
    name: nginx-sample-restore
    namespace: openshift-adp
  spec:
    backupName: nginx-sample-backup
    restorePVs: true     # Optional: true/false
  EOF
  ```

* Verify that the status of the Restore CR is Completed by entering the following command:
  ```
  velero get restore -n openshift-adp
  NAME                   BACKUP                STATUS      STARTED                         COMPLETED                       ERRORS   WARNINGS   CREATED                         SELECTOR
  nginx-sample-restore   nginx-sample-backup   Completed   2022-07-12 14:16:14 +0000 UTC   2022-07-12 14:16:41 +0000 UTC   0        4          2022-07-12 14:16:14 +0000 UTC   <none>

  oc get restore -n openshift-adp nginx-sample-restore -o jsonpath='{.status.phase}'
  ```

* Verify that the backup resources have been restored by entering the following command
  ```
  oc get all -n sample-backup
  NAME                         READY   STATUS    RESTARTS   AGE
  pod/nginx-5ffbd89cfd-wlbsw   1/1     Running   0          90s
  
  NAME            TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)    AGE
  service/nginx   ClusterIP   172.30.21.198   <none>        8080/TCP   88s
  
  NAME                    READY   UP-TO-DATE   AVAILABLE   AGE
  deployment.apps/nginx   1/1     1            1           89s
  
  NAME                               DESIRED   CURRENT   READY   AGE
  replicaset.apps/nginx-5ffbd89cfd   1         1         1       89s
  
  NAME                                   IMAGE   REPOSITORY                                                                   TAGS     UPDATED
  imagestream.image.openshift.io/nginx   default-route-openshift-image-registry.apps.  ocp4.example.net/sample-backup/nginx   v1.0   About a minute ago
  
  NAME                             HOST/PORT                     PATH   SERVICES     PORT       TERMINATION   WILDCARD
  route.route.openshift.io/nginx   nginx.apps.ocp4.example.net          nginx        8080-tcp                 None
  
  oc get pvc -n sample-backup
  NAME            STATUS   VOLUME                                     CAPACITY   ACCESS   MODES   STORAGECLASS   AGE
  nginx-storage   Bound    pvc-088935bc-a85f-402b-b3fe-ddf449f60dd1   5Gi          RWO            nfs-storage    2m4s
  
  oc -n sample-backup rsh nginx-5ffbd89cfd-wlbsw  
  Defaulted container "nginx" out of: nginx, restic-wait (init)
  sh-4.4$ df -h /data
  Filesystem                                                                                 Size  Used Avail Use% Mounted on
  10.74.251.171:/nfs/  sample-backup-nginx-storage-pvc-088935bc-a85f-402b-b3fe-ddf449f60dd1  192G  127G     65G  67% /data
  sh-4.4$ cat /data/test 
  hello
  sh-4.4$ exit
  ```

### Scheduling backups using Schedule CR
  ```
  cat << EOF | oc apply -f -
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
  ```
