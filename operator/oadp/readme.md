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

  alias velero='oc -n openshift-adp exec deployment/velero -c velero -it -- ./velero'
  velero get backup-locations -n openshift-adp
  ```

### Deploy test application
* Create a test pod:
  ```
  oc new-project sample-backup
  oc -n sample-backup new-app --name nginx --docker-image quay.io/redhattraining/hello-world-nginx:v1.0
  oc -n sample-backup expose svc/nginx --hostname nginx.apps.ocp4.example.com
  oc -n sample-backup set volumes deployment/nginx \
    --add --name nginx-storage --type pvc --claim-mode RWO --claim-size 5Gi --mount-path /data --claim-name nginx-storage

  oc rsh -n sample-backup $(oc get pods -n sample-backup --no-headers -o custom-columns=":metadata.name" | grep nginx) cat /data/test
  hello
  ```

### Backing up applications

* Create a Backup CR:
  ```
  export BACKUP_NAMESPACE=sample-backup
  export STORAGELOCATION=$(oc get backupStorageLocations -n openshift-adp -o jsonpath='{.items[0].metadata.name}')
  
  cat <<EOF | envsubst | oc apply -f -
  apiVersion: velero.io/v1
  kind: Backup
  metadata:
    name: sample-backup
    namespace: openshift-adp
  spec:
      hooks: {}
      includedNamespaces:
      - ${BACKUP_NAMESPACE}
      storageLocation: ${STORAGELOCATION}
      defaultVolumesToRestic: true 
      ttl: 720h0m0s
  EOF
  ```

* Verify that the status of the Backup CR is Completed:
  ```
  oc get backup -n openshift-adp sample-backup -o jsonpath='{.status.phase}'
  Completed

  alias velero='oc -n openshift-adp exec deployment/velero -c velero -it -- ./velero'
  velero get backup -n openshift-adp
  NAME            STATUS      ERRORS   WARNINGS   CREATED                         EXPIRES   STORAGE LOCATION   SELECTOR
  sample-backup   Completed   0        0          2023-12-14 05:26:05 +0000 UTC   29d       dpa-sample-1       <none>
  ```

* Verify whether there is backup data in "my minio/ocp backup/velo/backups/sample backup":
  ```
  oc rsh -n minio deployments/minio mc ls my-minio/oadp-bucket/velero/backups/sample-backu
  
  [2023-12-14 05:26:15 UTC]    29B STANDARD sample-backup-csi-volumesnapshotclasses.json.gz
  [2023-12-14 05:26:16 UTC]    29B STANDARD sample-backup-csi-volumesnapshotcontents.json.gz
  [2023-12-14 05:26:16 UTC]    29B STANDARD sample-backup-csi-volumesnapshots.json.gz
  [2023-12-14 05:26:15 UTC]    27B STANDARD sample-backup-itemoperations.json.gz
  [2023-12-14 05:26:15 UTC]  11KiB STANDARD sample-backup-logs.gz
  [2023-12-14 05:26:15 UTC]   902B STANDARD sample-backup-podvolumebackups.json.gz
  [2023-12-14 05:26:15 UTC]   899B STANDARD sample-backup-resource-list.json.gz
  [2023-12-14 05:26:15 UTC]    49B STANDARD sample-backup-results.gz
  [2023-12-14 05:26:15 UTC]    29B STANDARD sample-backup-volumesnapshots.json.gz
  [2023-12-14 05:26:15 UTC] 157KiB STANDARD sample-backup.tar.gz
  [2023-12-14 05:26:16 UTC] 3.6KiB STANDARD velero-backup.json
  ```

* If a backup error occurs, can view the Log by the following method
  ```
  alias velero='oc -n openshift-adp exec deployment/velero -c velero -it -- ./velero'

  velero backup logs sample-backup
  velero describe backup sample-backup
  ```
###  Restoring applications
* Delete the namespace to back up the object:
  ```
  oc delete project sample-backup
  ```
  
* Creating a Restore CR:
  ```
  oc get backup -n openshift-adp
  NAME            AGE
  sample-backup   5m30s

  export BACKUP_NAME=sample-backup
  
  cat <<EOF | envsubst | oc apply -f -
  apiVersion: velero.io/v1
  kind: Restore
  metadata:
    name: sample-restore
    namespace: openshift-adp
  spec:
    backupName: ${BACKUP_NAME}
    restorePVs: true
  EOF
  ```

* Verify that the status of the Restore CR is Completed by entering the following command:
  ```
  oc get restore -n openshift-adp sample-restore -o jsonpath='{.status.phase}'
  Completed

  alias velero='oc -n openshift-adp exec deployment/velero -c velero -it -- ./velero'
  velero get restore -n openshift-adp
  NAME             BACKUP          STATUS      STARTED                         COMPLETED                       ERRORS   WARNINGS   CREATED                         SELECTOR
  sample-restore   sample-backup   Completed   2023-12-14 05:35:15 +0000 UTC   2023-12-14 05:35:53 +0000 UTC   0        11         2023-12-14 05:35:15 +0000 UTC   <none>
  ```

* Verify that the backup resources have been restored by entering the following command:
  ```
  oc get all -n sample-backup  
  oc get pvc -n sample-backup
  oc rsh -n sample-backup $(oc get pods -n sample-backup --no-headers -o custom-columns=":metadata.name" | grep nginx) cat /data/test
  ```

* If a restore error occurs, can view the Log by the following method
  ```
  alias velero='oc -n openshift-adp exec deployment/velero -c velero -it -- ./velero'

  velero restore logs sample-restore
  velero describe restore sample-restore
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
