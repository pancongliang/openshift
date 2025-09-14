##  OADP Application backup and restore

### Install Install Object Storage

* Install [Minio and create oadp-bucket](/storage/minio/readme.md)

### Install and configure OADP Operator

* Install OADP Operator:
  ```
  export CHANNEL_NAME="stable-1.4"
  export CATALOG_SOURCE_NAME="redhat-operators"
  export NAMESPACE="openshift-adp"
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
  oc get backup -n openshift-adp

  velero get backup
  ```

* Viewing Backup details:
  ```
  $ velero backup describe sample-backup-1 --details
  ···
  Backup Volumes:
    Velero-Native Snapshots: <none included>
    CSI Snapshots: <none included>
    Pod Volume Backups - kopia:
      Completed:
        sample-backup/nginx-5945948fc6-9tdvm: nginx-html
  ```
  
* Viewing PodVolumeBackup:
  ```
  $ oc get PodVolumeBackup -n openshift-adp
  NAME                    STATUS      CREATED   NAMESPACE       POD                      VOLUME       UPLOADER TYPE   STORAGE LOCATION   AGE
  sample-backup-1-gmt8g   Completed   39s       sample-backup   nginx-5945948fc6-9tdvm   nginx-html   kopia           dpa-sample-1       39s
  ```
  
* Verify that the backup data exists in the object storage:
  ```
  $ mc ls my-minio/oadp-bucket/velero/backups/sample-backup-1
  [2025-09-14 10:25:35 UTC]    29B STANDARD sample-backup-1-csi-volumesnapshotclasses.json.gz
  [2025-09-14 10:25:35 UTC]    29B STANDARD sample-backup-1-csi-volumesnapshotcontents.json.gz
  [2025-09-14 10:25:35 UTC]    29B STANDARD sample-backup-1-csi-volumesnapshots.json.gz
  [2025-09-14 10:25:35 UTC]    27B STANDARD sample-backup-1-itemoperations.json.gz
  [2025-09-14 10:25:35 UTC]  12KiB STANDARD sample-backup-1-logs.gz
  [2025-09-14 10:25:35 UTC]   904B STANDARD sample-backup-1-podvolumebackups.json.gz
  [2025-09-14 10:25:35 UTC] 1.1KiB STANDARD sample-backup-1-resource-list.json.gz
  [2025-09-14 10:25:35 UTC]    49B STANDARD sample-backup-1-results.gz
  [2025-09-14 10:25:35 UTC]   376B STANDARD sample-backup-1-volumeinfo.json.gz
  [2025-09-14 10:25:35 UTC]    29B STANDARD sample-backup-1-volumesnapshots.json.gz
  [2025-09-14 10:25:35 UTC]  37KiB STANDARD sample-backup-1.tar.gz
  [2025-09-14 10:25:35 UTC] 3.0KiB STANDARD velero-backup.json
  
  $ mc ls my-minio/oadp-bucket/velero/kopia/sample-backup/
  [2025-09-14 10:25:35 UTC] 4.2KiB STANDARD p74e338399e964208fd55a48ea1b8227b-s85e49dbb4de8b303138
  [2025-09-14 10:25:35 UTC] 4.2KiB STANDARD q34ba78474d24679248a0531fcca59d05-s064ac8fac7310fa0138
  [2025-09-14 10:25:35 UTC] 4.3KiB STANDARD qe1a5112a6281ef0e09f97d1f69aa29f5-s85e49dbb4de8b303138
  [2025-09-14 10:25:35 UTC]   379B STANDARD xn0_0da1edd4eb4e8eaf4f06fdf79f45e04a-s85e49dbb4de8b303138-c1
  [2025-09-14 10:25:35 UTC]   143B STANDARD xn0_53b2666e0bf8547c4c8cbae3a7bb7ed9-s064ac8fac7310fa0138-c1

  ```

* If a backup error occurs, can view the Log by the following method
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
  
* Creating a Restore CR:
  ```
  velero create restore sample-restore-1 --from-backup sample-backup-1
  ```

* Verify that the status of the Restore is Completed by entering the following command:
  ```
  oc get restore -n openshift-adp sample-restore-1 -o jsonpath='{.status.phase}'

  velero get restore -n openshift-adp
  NAME             BACKUP          STATUS      STARTED                         COMPLETED                       ERRORS   WARNINGS   CREATED                         SELECTOR
  sample-restore   sample-backup   Completed   2023-12-14 05:35:15 +0000 UTC   2023-12-14 05:35:53 +0000 UTC   0        11         2023-12-14 05:35:15 +0000 UTC   <none>
  ```

* Verify that the backup resources have been restored by entering the following command:
  ```
  oc get all -n sample-backup  
  oc get pvc -n sample-backup

  export POD_NAME=$(oc get pods -n sample-backup --no-headers -o custom-columns=":metadata.name" | grep nginx | head -n 1)
  export ROUTE_HOST=$(oc get route nginx -n sample-backup -o jsonpath='{.spec.host}')

  $ curl http://$ROUTE_HOST
  Hello OpenShift!
  ```

* If a restore error occurs, can view the Log by the following method
  ```
  velero restore logs sample-restore-1
  velero describe restore sample-restore-1
  ```
  
### Scheduling backups using Schedule CR
* Create a Schedule CR, as in the following example:  
  ```
  export BACKUP_NAMESPACE=sample-backup
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
      - ${BACKUP_NAMESPACE}
      storageLocation: ${STORAGELOCATION}
      defaultVolumesToRestic: true 
      ttl: 720h0m0s
  EOF
  ```

* Verify that the status of the Schedule CR:
  ```
  oc get schedule -n openshift-adp
  NAME                           STATUS    SCHEDULE       LASTBACKUP   AGE   PAUSED
  nginx-sample-backup-schedule   Enabled   */10 * * * *   2m11s        18m 

  oc get backup -n openshift-adp
  NAME                                    AGE
  sample-backup-schedule-20231214055040   12m
  sample-backup-schedule-20231214060040   2m26s
  sample-backup                           37m
 
  oc get backup -n openshift-adp sample-backup-schedule-20231214055040  -o jsonpath='{.status.phase}'
  Completed
  ```
