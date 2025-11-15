##  OADP Application backup and restore

### Install Install Object Storage

* Install [Minio and create oadp-bucket](/storage/minio/readme.md)

### Install and configure OADP Operator

* Install OADP Operator:
  ```
  export SUB_CHANNEL="stable-1.4"
  export CATALOG_SOURCE="redhat-operators"
  export OPERATOR_NS="openshift-adp"
  
  curl -s https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/operator/oadp/01-operator.yaml | envsubst | oc apply -f -
  curl -s https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/operator/approve_ip.sh | bash
  ```

* Create a Secret named "cloud-credentials" in the openshift-adp project to allow access to Minio:
  ```
  cat << EOF > credentials-velero
  [default]
  aws_access_key_id=minioadmin
  aws_secret_access_key=minioadmin
  EOF

  oc create secret generic cloud-credentials -n openshift-adp --from-file cloud=credentials-velero
  rm -rf credentials-velero
  ```

* Create DataProtectionApplication:
  ```
  export S3URL=$(oc get route minio -n minio -o jsonpath='http://{.spec.host}')
  export BUCKET_NAME="oadp-bucket"
  
  curl -s https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/operator/oadp/02-dpa.yaml | envsubst | oc apply -f -
  ```

* View the Resources related to the DataProtectionApplication object:
  ```
  oc get po -n openshift-adp
  oc get dataprotectionapplication -n openshift-adp
  oc get backupStorageLocations -n openshift-adp

  echo "alias velero='oc -n openshift-adp exec deployment/velero -c velero -it -- ./velero'" >> ~/.bashrc && source ~/.bashrc
  velero get backup-locations
  ```

### Deploy test application
* Create a test pod:
  ```
  oc new-project sample-backup
  oc -n sample-backup new-app --name nginx --docker-image quay.io/redhattraining/hello-world-nginx:v1.0
  oc -n sample-backup expose svc/nginx
  oc -n sample-backup set volumes deployment/nginx \
  --add --name nginx-html --type pvc --claim-mode RWO --claim-size 5Gi --mount-path /usr/share/nginx/html --claim-name nginx-html
  
  export POD_NAME=$(oc get pods -n sample-backup --no-headers -o custom-columns=":metadata.name" | grep nginx | head -n 1)
  export ROUTE_HOST=$(oc get route nginx -n sample-backup -o jsonpath='{.spec.host}')
  oc rsh -n sample-backup $POD_NAME sh -c 'echo "Hello OpenShift!" > /usr/share/nginx/html/index.html'

  $ curl http://$ROUTE_HOST
  Hello OpenShift!
  ```

### Application Backup and Restore with FSB
#### Backing up applications

* Modify Deployment to Add Annotation to Pods, Specifying Which PVC(s) Should Be Backed Up:
  ```
  export NAMESPACE=sample-backup
  export DEPLOYMENT=nginx
  
  # Single volume
  export VOLUME_NAME=nginx-html
  oc patch deployment $DEPLOYMENT -n $NAMESPACE --type=merge \
    -p "{\"spec\":{\"template\":{\"metadata\":{\"annotations\":{\"backup.velero.io/backup-volumes\":\"$VOLUME_NAME\"}}}}}"

  # Multiple volumes
  export VOLUME_NAMES="nginx-html,nginx-logs"
  oc patch deployment $DEPLOYMENT -n $NAMESPACE --type=merge \
    -p "{\"spec\":{\"template\":{\"metadata\":{\"annotations\":{\"backup.velero.io/backup-volumes\":\"$VOLUME_NAMES\"}}}}}"

  ```
* Create a FSB Backup:
  ```
  velero backup create sample-backup-1 --include-namespaces $NAMESPACE
  ```

* Verify that the status of the Backup is Completed:
  ```
  oc get backup -n openshift-adp sample-backup-1 -o jsonpath='{.status.phase}'

  $ velero get backup
  NAME              STATUS                       ERRORS   WARNINGS   CREATED                         EXPIRES   STORAGE LOCATION   SELECTOR
  sample-backup-1   Completed                    0        0          2025-09-14 13:38:24 +0000 UTC   29d       dpa-sample-1       <none>
  ```

* Viewing Backup details:
  ```
  $ velero backup describe sample-backup-1 --details
  ···
  Velero-Native Snapshot PVs:  auto
  Snapshot Move Data:          false
  Data Mover:                  velero
  ···
  Backup Volumes:
    Velero-Native Snapshots: <none included>
    CSI Snapshots: <none included>
    Pod Volume Backups - kopia:
      Completed:
        sample-backup/nginx-5945948fc6-5km6h: nginx-html
  ```
  
* Viewing PodVolumeBackup:
  ```
  $ oc get PodVolumeBackup -n openshift-adp
  NAME                    STATUS      CREATED   NAMESPACE       POD                      VOLUME       UPLOADER TYPE   STORAGE LOCATION   AGE
  sample-backup-1-42bxs   Completed   38m       sample-backup   nginx-5945948fc6-5km6h   nginx-html   kopia           dpa-sample-1       38m
  ```
  
* Verify that the backup data exists in the object storage:
  ```
  $ mc ls my-minio/oadp-bucket/velero/backups/sample-backup-1
  [2025-09-14 13:38:26 UTC]    29B STANDARD sample-backup-1-csi-volumesnapshotclasses.json.gz
  [2025-09-14 13:38:26 UTC]    29B STANDARD sample-backup-1-csi-volumesnapshotcontents.json.gz
  [2025-09-14 13:38:26 UTC]    29B STANDARD sample-backup-1-csi-volumesnapshots.json.gz
  [2025-09-14 13:38:26 UTC]    27B STANDARD sample-backup-1-itemoperations.json.gz
  [2025-09-14 13:38:26 UTC]  12KiB STANDARD sample-backup-1-logs.gz
  [2025-09-14 13:38:26 UTC]   907B STANDARD sample-backup-1-podvolumebackups.json.gz
  [2025-09-14 13:38:26 UTC]   861B STANDARD sample-backup-1-resource-list.json.gz
  [2025-09-14 13:38:26 UTC]    49B STANDARD sample-backup-1-results.gz
  [2025-09-14 13:38:26 UTC]   379B STANDARD sample-backup-1-volumeinfo.json.gz
  [2025-09-14 13:38:26 UTC]    29B STANDARD sample-backup-1-volumesnapshots.json.gz
  [2025-09-14 13:38:26 UTC]  32KiB STANDARD sample-backup-1.tar.gz
  [2025-09-14 13:38:26 UTC] 3.0KiB STANDARD velero-backup.json
  
  $ mc ls my-minio/oadp-bucket/velero/kopia/sample-backup/
  [2025-09-14 13:38:25 UTC]   768B STANDARD _log_20250914133825_3c95_1757857105_1757857105_1_39dc3f2f0ada99fadb912112b85a0af5
  [2025-09-14 13:38:26 UTC] 1.3KiB STANDARD _log_20250914133826_84d9_1757857106_1757857106_1_19a93955d99fac4a64e9eeb773092324
  [2025-09-14 13:38:24 UTC]    30B STANDARD kopia.blobcfg
  [2025-09-14 13:38:25 UTC] 1.0KiB STANDARD kopia.repository
  [2025-09-14 13:38:26 UTC] 4.2KiB STANDARD p04335357c0eb0a05c3ebb92191969d2c-s095e2ecfd5d0358e138
  [2025-09-14 13:38:26 UTC] 4.2KiB STANDARD q7bb67af4332052e6066b9a5d6002b225-sf56831d0ab20072d138
  [2025-09-14 13:38:25 UTC] 4.2KiB STANDARD qda7f3255c7271f564a90ec9157f9a797-se38e1b07e0001d60138
  [2025-09-14 13:38:26 UTC] 4.3KiB STANDARD qf39d3d6cac5503d8e71dddbea00890b4-s095e2ecfd5d0358e138
  [2025-09-14 13:38:26 UTC]   311B STANDARD xn0_2f997c24108f3937a1e2593625a98512-s095e2ecfd5d0358e138-c1
  [2025-09-14 13:38:26 UTC]   143B STANDARD xn0_83100827180f4da6408c45d7789935bc-sf56831d0ab20072d138-c1
  [2025-09-14 13:38:25 UTC]   143B STANDARD xn0_c5b9a5f36ead20a406d7059e495d905c-se38e1b07e0001d60138-c1
  ```

* If a backup error occurs, can view the Log by the following method:
  ```
  velero backup logs sample-backup-1
  velero describe backup sample-backup-1
  ```
  
#### Restore Testing
* Delete the namespace to back up the object:
  ```
  oc delete project $NAMESPACE
  oc get pv -o json | jq -r ".items[] | select(.spec.claimRef.namespace==\"$NAMESPACE\") | .metadata.name" | xargs -r oc delete pv
  ```
  
* Create a Restore from Backup with Velero:
  ```
  velero create restore sample-restore-1 --from-backup sample-backup-1
  ```

* Verify that the status of the Restore is Completed by entering the following command:
  ```
  oc get restore -n openshift-adp sample-restore-1 -o jsonpath='{.status.phase}'

  $ velero get restore
  NAME               BACKUP            STATUS      STARTED                         COMPLETED                       ERRORS   WARNINGS              
  sample-restore-1   sample-backup-1   Completed   2025-09-14 14:19:00 +0000 UTC   2025-09-14 14:19:21 +0000 UTC   0        6
  ```

* Verify that the backup resources have been restored by entering the following command:
  ```
  oc get all -n $NAMESPACE 
  oc get pvc,pv -n $NAMESPACE 
  
  export ROUTE_HOST=$(oc get route nginx -n $NAMESPACE  -o jsonpath='{.spec.host}')
  $ curl http://$ROUTE_HOST
  Hello OpenShift!
  ```

* View the log data related to this restore in the object storage:
  ```
  $ mc ls my-minio/oadp-bucket/velero/restores/sample-restore-1/
  [2025-09-14 14:19:21 UTC]    27B STANDARD restore-sample-restore-1-itemoperations.json.gz
  [2025-09-14 14:19:21 UTC] 8.2KiB STANDARD restore-sample-restore-1-logs.gz
  [2025-09-14 14:19:21 UTC]   518B STANDARD restore-sample-restore-1-resource-list.json.gz
  [2025-09-14 14:19:21 UTC]   306B STANDARD restore-sample-restore-1-results.gz
  [2025-09-14 14:19:21 UTC]   255B STANDARD sample-restore-1-volumeinfo.json.gz
  ```
  
* If a restore error occurs, can view the Log by the following method:
  ```
  velero restore logs sample-restore-1
  velero describe restore sample-restore-1
  ```


### Application Backup and Restore with CSI Snapshot
#### Backing up applications

* A default `StorageClass` and `VolumeSnapshotClass` must be available as prerequisites:
  ```
  $ oc get storageclass
  NAME                PROVISIONER       RECLAIMPOLICY   VOLUMEBINDINGMODE      ALLOWVOLUMEEXPANSION   AGE
  gp3-csi (default)   ebs.csi.aws.com   Delete          WaitForFirstConsumer   true                   3h10m

  $ oc get volumesnapshotclass
  NAME          DRIVER            DELETIONPOLICY   AGE
  csi-aws-vsc   ebs.csi.aws.com   Delete           3h10m
  ```
  
* Label the `VolumeSnapshotClass` with velero.io/csi-volumesnapshot-class:
  ```
  oc label volumesnapshotclass $(oc get volumesnapshotclass -o=jsonpath='{.items[?(@.metadata.annotations.snapshot\.storage\.kubernetes\.io/is-default-class=="true")].metadata.name}') velero.io/csi-volumesnapshot-class="true"
  ```
  
* Disable Velero’s NodeAgent/Kopia file system backup and use only CSI snapshots:
  ```
  oc patch dpa dpa-sample -n openshift-adp --type=json -p='[{"op":"remove","path":"/spec/configuration/nodeAgent"}]'
  oc patch dpa dpa-sample -n openshift-adp --type=merge -p '{"spec":{"configuration":{"velero":{"defaultPlugins":["openshift","aws","csi"],"featureFlags":["EnableCSI"]}}}}'
  ```
  
* Remove the backup.velero.io/backup-volumes annotation; otherwise, Velero will use FSB:
  ```
  export NAMESPACE=sample-backup
  export DEPLOYMENT=nginx

  oc patch deploy $DEPLOYMENT -n $NAMESPACE --type=json -p '[{"op": "remove", "path": "/spec/template/metadata/annotations"}]'
  ```
  
* Create a CSI Snapshot Backup:

  ```
  velero backup create sample-backup-2 --include-namespaces $NAMESPACE

  # The VolumeSnapshot is automatically deleted after the backup
  oc get volumesnapshot -n $NAMESPACE -w
  ```

* Verify that the status of the Backup is Completed:
  ```
  oc get backup -n openshift-adp sample-backup-2 -o jsonpath='{.status.phase}'

  $ velero get backup sample-backup-2
  NAME              STATUS      ERRORS   WARNINGS   CREATED                         EXPIRES   STORAGE LOCATION   SELECTOR
  sample-backup-2   Completed   0        0          2025-09-14 15:17:59 +0000 UTC   29d       dpa-sample-1       <none>
  ```

* Viewing VolumeSnapshotContent Objects:
  ```
  oc get volumesnapshotcontent
  NAME                                               READYTOUSE   RESTORESIZE   DELETIONPOLICY   DRIVER            VOLUMESNAPSHOTCLASS   VOLUMESNAPSHOT                              VOLUMESNAPSHOTNAMESPACE                   AGE
  snapcontent-66017d1c-633a-4214-a61a-e99f21a0d05a   true         5368709120    Retain           ebs.csi.aws.com   csi-aws-vsc           name-4d3484a3-6d69-491f-a58b-565b73326a47   ns-4d3484a3-6d69-491f-a58b-565b73326a47   110s
  ```
* Viewing Backup details:
  ```
  $ velero backup describe sample-backup-2 --details
  ···
  Velero-Native Snapshot PVs:  auto
  Snapshot Move Data:          false
  Data Mover:                  velero
  ···
  Backup Volumes:
    Velero-Native Snapshots: <none included>
    CSI Snapshots:
      sample-backup/nginx-html:
        Snapshot:
          Operation ID: sample-backup/velero-nginx-html-k6sqn/2025-09-14T15:18:05Z
          Snapshot Content Name: snapcontent-66017d1c-633a-4214-a61a-e99f21a0d05a
          Storage Snapshot ID: snap-0bd4d75689ab7b952
          Snapshot Size (bytes): 5368709120
          CSI Driver: ebs.csi.aws.com
    Pod Volume Backups: <none included>
  ```

* Verify that the backup data exists in the object storage:
  ```
  $ mc ls my-minio/oadp-bucket/velero/backups/sample-backup-2
  [2025-09-14 15:18:05 UTC]   426B STANDARD sample-backup-2-csi-volumesnapshotclasses.json.gz
  [2025-09-14 15:18:05 UTC]   747B STANDARD sample-backup-2-csi-volumesnapshotcontents.json.gz
  [2025-09-14 15:18:05 UTC]   706B STANDARD sample-backup-2-csi-volumesnapshots.json.gz
  [2025-09-14 15:18:54 UTC]   358B STANDARD sample-backup-2-itemoperations.json.gz
  [2025-09-14 15:18:05 UTC]  12KiB STANDARD sample-backup-2-logs.gz
  [2025-09-14 15:18:05 UTC]    29B STANDARD sample-backup-2-podvolumebackups.json.gz
  [2025-09-14 15:18:05 UTC]   787B STANDARD sample-backup-2-resource-list.json.gz
  [2025-09-14 15:18:05 UTC]    49B STANDARD sample-backup-2-results.gz
  [2025-09-14 15:18:55 UTC]   387B STANDARD sample-backup-2-volumeinfo.json.gz
  [2025-09-14 15:18:05 UTC]    29B STANDARD sample-backup-2-volumesnapshots.json.gz
  [2025-09-14 15:18:55 UTC]  31KiB STANDARD sample-backup-2.tar.gz
  [2025-09-14 15:18:55 UTC] 3.3KiB STANDARD velero-backup.json
  ```

#### Restore Testing
* Delete the namespace to back up the object:
  ```
  oc delete project $NAMESPACE
  oc get pv -o json | jq -r ".items[] | select(.spec.claimRef.namespace==\"$NAMESPACE\") | .metadata.name" | xargs -r oc delete pv
  ```
  
* Create a Restore from Backup with Velero:
  ```
  velero create restore sample-restore-2 --from-backup sample-backup-2
  ```

* Verify that the status of the Restore is Completed by entering the following command:
  ```
  oc get restore -n openshift-adp sample-restore-2 -o jsonpath='{.status.phase}'

  $ velero get restore sample-restore-2
  NAME               BACKUP            STATUS      STARTED                         COMPLETED                       ERRORS   WARNINGS
  sample-restore-2   sample-backup-2   Completed   2025-09-14 15:30:08 +0000 UTC   2025-09-14 15:30:10 +0000 UTC   0        7 

  $ oc get volumesnapshot -n $NAMESPACE
  NAME                      READYTOUSE   SOURCEPVC   SOURCESNAPSHOTCONTENT           RESTORESIZE   SNAPSHOTCLASS   SNAPSHOTCONTENT                 CREATIONTIME   AGE
  velero-nginx-html-k6sqn   true                     velero-nginx-html-k6sqn-jbbcf   5Gi           csi-aws-vsc     velero-nginx-html-k6sqn-jbbcf   14m            117s
  ```

* Verify that the backup resources have been restored by entering the following command:
  ```
  oc get all -n $NAMESPACE 
  oc get pvc,pv -n $NAMESPACE 
  oc get VolumeSnapshot -n $NAMESPACE
  
  export ROUTE_HOST=$(oc get route nginx -n $NAMESPACE  -o jsonpath='{.spec.host}')
  $ curl http://$ROUTE_HOST
  Hello OpenShift!
  ```

* View the log data related to this restore in the object storage:
  ```
  $ mc ls my-minio/oadp-bucket/velero/restores/sample-restore-2/
  [2025-09-14 15:30:10 UTC]    27B STANDARD restore-sample-restore-2-itemoperations.json.gz
  [2025-09-14 15:30:10 UTC] 8.6KiB STANDARD restore-sample-restore-2-logs.gz
  [2025-09-14 15:30:10 UTC]   620B STANDARD restore-sample-restore-2-resource-list.json.gz
  [2025-09-14 15:30:10 UTC]   305B STANDARD restore-sample-restore-2-results.gz
  [2025-09-14 15:30:10 UTC]   217B STANDARD sample-restore-2-volumeinfo.json.g
  ```

### Backing up and restoring CSI snapshots data movement
#### Backing up applications

* A default `StorageClass` and `VolumeSnapshotClass` must be available as prerequisites:
  ```
  $ oc get storageclass
  NAME                PROVISIONER       RECLAIMPOLICY   VOLUMEBINDINGMODE      ALLOWVOLUMEEXPANSION   AGE
  gp3-csi (default)   ebs.csi.aws.com   Delete          WaitForFirstConsumer   true                   3h10m

  $ oc get volumesnapshotclass
  NAME          DRIVER            DELETIONPOLICY   AGE
  csi-aws-vsc   ebs.csi.aws.com   Delete           3h10m
  ```

* Enable NodeAgent/Kopia for file system backup and configure Velero to move CSI snapshot data while disabling default FSB:
  ```
  oc patch dpa dpa-sample -n openshift-adp --type=merge -p '{"spec":{"configuration":{"nodeAgent":{"enable":true,"uploaderType":"kopia"},"velero":{"defaultSnapshotMoveData":true,"defaultVolumesToFSBackup":false}}}}'
  ```
  
* Remove the backup.velero.io/backup-volumes annotation; otherwise, Velero will use FSB:
  ```
  export NAMESPACE=sample-backup
  export DEPLOYMENT=nginx

  oc patch deploy $DEPLOYMENT -n $NAMESPACE --type=json -p '[{"op": "remove", "path": "/spec/template/metadata/annotations"}]'
  ```
  
* Create a Snapshot Move Data Backup:
  ```
  velero create backup sample-backup-3 --include-namespaces $NAMESPACE

  # The VolumeSnapshot is automatically deleted after the backup
  oc get volumesnapshot -n $NAMESPACE -w
  oc get VolumeSnapshotContent -w
  
  ```

* Verify that the status of the Backup is Completed:
  ```
  oc get backup -n openshift-adp sample-backup-3 -o jsonpath='{.status.phase}'

  $ velero get backup sample-backup-3
  NAME              STATUS      ERRORS   WARNINGS   CREATED                         EXPIRES   STORAGE LOCATION   SELECTOR
  sample-backup-3   Completed   0        0          2025-09-14 15:44:16 +0000 UTC   29d       dpa-sample-1       <none>
  ```
  
* Viewing Backup details:
  ```
  $ velero backup describe sample-backup-3 --details
  ···
  Velero-Native Snapshot PVs:  auto
  Snapshot Move Data:          true
  Data Mover:                  velero
  ···
  Backup Volumes:
    Velero-Native Snapshots: <none included>
    CSI Snapshots:
      sample-backup/nginx-html:
        Data Movement:
          Operation ID: du-ceb95122-428a-46e4-879f-37faad66bbd5.ab98b720-6d09-4f1bcb737
          Data Mover: velero
          Uploader Type: kopia
          Moved data Size (bytes): 17
    Pod Volume Backups: <none included>
  ```
* Viewing the DataUpload Object  
  ```
  $ oc get DataUpload -n openshift-adp -l velero.io/backup-name=sample-backup-3
  NAME                    STATUS      STARTED   BYTES DONE   TOTAL BYTES   STORAGE LOCATION   AGE     NODE
  sample-backup-3-sdtk4   Completed   3m        17           17            dpa-sample-1       3m55s   ip-10-0-85-183.ap-northeast-1.compute.internal
  ```
  
* Verify that the backup data exists in the object storage:
  ```
  $ mc ls my-minio/oadp-bucket/velero/backups/sample-backup-3
  [2025-09-14 15:44:22 UTC]    29B STANDARD sample-backup-3-csi-volumesnapshotclasses.json.gz
  [2025-09-14 15:44:22 UTC]    29B STANDARD sample-backup-3-csi-volumesnapshotcontents.json.gz
  [2025-09-14 15:44:22 UTC]    29B STANDARD sample-backup-3-csi-volumesnapshots.json.gz
  [2025-09-14 15:45:20 UTC]   387B STANDARD sample-backup-3-itemoperations.json.gz
  [2025-09-14 15:44:22 UTC]  12KiB STANDARD sample-backup-3-logs.gz
  [2025-09-14 15:44:22 UTC]    29B STANDARD sample-backup-3-podvolumebackups.json.gz
  [2025-09-14 15:44:22 UTC]   701B STANDARD sample-backup-3-resource-list.json.gz
  [2025-09-14 15:44:22 UTC]    49B STANDARD sample-backup-3-results.gz
  [2025-09-14 15:45:20 UTC]   429B STANDARD sample-backup-3-volumeinfo.json.gz
  [2025-09-14 15:44:22 UTC]    29B STANDARD sample-backup-3-volumesnapshots.json.gz
  [2025-09-14 15:45:20 UTC]  34KiB STANDARD sample-backup-3.tar.gz
  [2025-09-14 15:45:20 UTC] 3.2KiB STANDARD velero-backup.json

  $ mc ls my-minio/oadp-bucket/velero/kopia/sample-backup
  [2025-09-14 13:38:25 UTC]   768B STANDARD _log_20250914133825_3c95_1757857105_1757857105_1_39dc3f2f0ada99fadb912112b85a0af5
  [2025-09-14 13:38:26 UTC] 1.3KiB STANDARD _log_20250914133826_84d9_1757857106_1757857106_1_19a93955d99fac4a64e9eeb773092324
  [2025-09-14 14:42:35 UTC] 1.8KiB STANDARD _log_20250914144235_bb97_1757860955_1757860955_1_f5233157c277d91694463d8fc06ee908
  [2025-09-14 15:45:18 UTC] 1.3KiB STANDARD _log_20250914154518_3075_1757864718_1757864718_1_91166221b30481ee80737d54cf5e5dbf
  [2025-09-14 15:46:01 UTC] 1.0KiB STANDARD _log_20250914154601_fbee_1757864761_1757864761_1_679490f89491f1ce4537acdd522e8d9f
  [2025-09-14 13:38:24 UTC]    30B STANDARD kopia.blobcfg
  [2025-09-14 15:46:01 UTC] 1.1KiB STANDARD kopia.maintenance
  [2025-09-14 13:38:25 UTC] 1.0KiB STANDARD kopia.repository
  [2025-09-14 13:38:26 UTC] 4.2KiB STANDARD p04335357c0eb0a05c3ebb92191969d2c-s095e2ecfd5d0358e138
  [2025-09-14 15:45:18 UTC] 4.2KiB STANDARD pf2c2e6a86ccad6b9ba6f2e2f42f79c0a-s99dd4bfc51e76224138
  [2025-09-14 15:45:18 UTC] 4.2KiB STANDARD q6c35211cca8226708ad13e655a79431a-se2d250fcf5b1cc95138
  [2025-09-14 13:38:26 UTC] 4.2KiB STANDARD q7bb67af4332052e6066b9a5d6002b225-sf56831d0ab20072d138
  [2025-09-14 15:45:18 UTC] 4.3KiB STANDARD qb2c0f221fbed74d2990ab0abd68e2560-s99dd4bfc51e76224138
  [2025-09-14 13:38:25 UTC] 4.2KiB STANDARD qda7f3255c7271f564a90ec9157f9a797-se38e1b07e0001d60138
  [2025-09-14 13:38:26 UTC] 4.3KiB STANDARD qf39d3d6cac5503d8e71dddbea00890b4-s095e2ecfd5d0358e138
  [2025-09-14 15:45:18 UTC]   311B STANDARD xn0_12df911eaadc23fb3457fdbcfd2afff7-s99dd4bfc51e76224138-c1
  [2025-09-14 13:38:26 UTC]   311B STANDARD xn0_2f997c24108f3937a1e2593625a98512-s095e2ecfd5d0358e138-c1
  [2025-09-14 15:45:18 UTC]   143B STANDARD xn0_5a5a3e39001496d63159bfed338ccf1a-se2d250fcf5b1cc95138-c1
  [2025-09-14 13:38:26 UTC]   143B STANDARD xn0_83100827180f4da6408c45d7789935bc-sf56831d0ab20072d138-c1
  [2025-09-14 13:38:25 UTC]   143B STANDARD xn0_c5b9a5f36ead20a406d7059e495d905c-se38e1b07e0001d60138-c1
  ```

#### Restore Testing
* Delete the namespace to back up the object:
  ```
  oc delete project $NAMESPACE
  oc get pv -o json | jq -r ".items[] | select(.spec.claimRef.namespace==\"$NAMESPACE\") | .metadata.name" | xargs -r oc delete pv
  ```
  
* Create a Restore from Backup with Velero:
  ```
  velero create restore sample-restore-3 --from-backup sample-backup-3
  oc get volumesnapshot -n $NAMESPACE
  ```

* Verify that the status of the Restore is Completed by entering the following command:
  ```
  oc get restore -n openshift-adp sample-restore-3 -o jsonpath='{.status.phase}'

  $ velero get restore sample-restore-3
  NAME               BACKUP            STATUS      STARTED                         COMPLETED                       ERRORS   WARNINGS
  sample-restore-3   sample-backup-3   Completed   2025-09-14 16:01:14 +0000 UTC   2025-09-14 16:02:00 +0000 UTC   0        8
  ```

* Viewing DataDownload Objects
  ```
  oc get DataDownload -n openshift-adp -l velero.io/restore-name=sample-restore-3
  NAME                     STATUS      STARTED   BYTES DONE   TOTAL BYTES   STORAGE LOCATION   AGE    NODE
  sample-restore-3-4mwbx   Completed   99s       17           17            dpa-sample-1       2m2s   ip-10-0-85-183.ap-northeast-1.compute.internal
  ```
  
* Verify that the backup resources have been restored by entering the following command:
  ```
  oc get all -n $NAMESPACE 
  oc get pvc,pv -n $NAMESPACE 
  oc get VolumeSnapshot -n $NAMESPACE 
  
  export ROUTE_HOST=$(oc get route nginx -n $NAMESPACE  -o jsonpath='{.spec.host}')
  $ curl http://$ROUTE_HOST
  Hello OpenShift!
  ```

* View the log data related to this restore in the object storage:
  ```
  $ mc ls my-minio/oadp-bucket/velero/restores/sample-restore-2/
  [2025-09-14 15:30:10 UTC]    27B STANDARD restore-sample-restore-2-itemoperations.json.gz
  [2025-09-14 15:30:10 UTC] 8.6KiB STANDARD restore-sample-restore-2-logs.gz
  [2025-09-14 15:30:10 UTC]   620B STANDARD restore-sample-restore-2-resource-list.json.gz
  [2025-09-14 15:30:10 UTC]   305B STANDARD restore-sample-restore-2-results.gz
  [2025-09-14 15:30:10 UTC]   217B STANDARD sample-restore-2-volumeinfo.json.g
  ```

### Scheduling backups using Schedule CR
* Create a Schedule CR, as in the following example:  
  ```
  export NAMESPACE=sample-backup
  export STORAGELOCATION=$(oc get backupStorageLocations -n openshift-adp -o jsonpath='{.items[0].metadata.name}')

  cat << EOF | oc apply -f -
  apiVersion: velero.io/v1
  kind: Schedule
  metadata:
    name: sample-backup-schedule
    namespace: openshift-adp
  spec:
    schedule: '*/10 * * * *'
    template:
      hooks: {}
      includedNamespaces:
      - ${NAMESPACE}
      storageLocation: ${STORAGELOCATION}
      defaultVolumesToRestic: true 
      ttl: 720h0m0s
  EOF
  ```

* Verify that the status of the Schedule CR:
  ```
  oc get schedule -n openshift-adp
  oc get backup -n openshift-adp 
  oc get backup -n openshift-adp sample-backup-schedule-20231214055040  -o jsonpath='{.status.phase}'
  ```
