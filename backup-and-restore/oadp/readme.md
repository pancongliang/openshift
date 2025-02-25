##  OADP Application backup and restore

### Deploy test application
* Create a test pod:
  ```
  oc new-project sample-backup
  oc new-app --name nginx --docker-image quay.io/redhattraining/hello-world-nginx:v1.0
  oc expose svc/nginx --hostname nginx.apps.ocp4.example.com
  curl -s nginx.apps.ocp4.example.com | grep Hello
      <h1>Hello, world from nginx!</h1>
  
  oc set volumes deployment/nginx \
    --add --name nginx-storage --type pvc --claim-class managed-nfs-storage \
    --claim-mode RWO --claim-size 5Gi --mount-path /data \
    --claim-name nginx-storage
  
  oc -n sample-backup rsh nginx-7c5fc86c75-qblm9
  sh-4.4$ df -h /data
  Filesystem                                                                               Size  Used Avail Use% Mounted on
  10.74.251.171:/nfs/sample-backup-nginx-storage-pvc-ed2735be-8c15-41eb-be1e-71ccb0e5db14  192G  127G   65G  67% /data
  sh-4.4$ cat /data/test
  hello
  sh-4.4$ exit
  
  oc get all -n sample-backup
  NAME                         READY   STATUS    RESTARTS   AGE
  pod/nginx-7c5fc86c75-qblm9   1/1     Running   0          90s
  
  NAME            TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)    AGE
  service/nginx   ClusterIP   172.30.137.187   <none>        8080/TCP   2m11s
  
  NAME                    READY   UP-TO-DATE   AVAILABLE   AGE
  deployment.apps/nginx   1/1     1            1           2m11s
  
  NAME                               DESIRED   CURRENT   READY   AGE
  replicaset.apps/nginx-675f9c6887   0         0         0       2m7s
  replicaset.apps/nginx-7557ff84     0         0         0       2m11s
  replicaset.apps/nginx-7c5fc86c75   1         1         1       90s
  
  NAME                                   IMAGE REPOSITORY                                                       TAGS     UPDATED
  imagestream.image.openshift.io/nginx   image-registry.openshift-image-registry.svc:5000/sample-backup/nginx   v1.0   2   minutes ago
  
  NAME                             HOST/PORT                     PATH   SERVICES   PORT       TERMINATION   WILDCARD
  route.route.openshift.io/nginx   nginx.apps.ocp4.example.com          nginx      8080-tcp                 None
  
  oc get pvc -n sample-backup
  NAME            STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS          AGE
  nginx-storage   Bound    pvc-ed2735be-8c15-41eb-be1e-71ccb0e5db14   5Gi        RWO            managed-nfs-storage   24m
  ```

### Install dependent components
* Install velero client on bastion machine:
  ```
  VERSION=v1.7.1
  cd ~/ && curl -OL https://github.com/vmware-tanzu/velero/releases/download/${VERSION}/velero-${VERSION}-linux-amd64.tar.gz
  tar -xvf velero-${VERSION}-linux-amd64.tar.gz
  mv velero-${VERSION}-linux-amd64/velero /usr/local/bin/
  ```

* Deploy [Minio and create oadp-bucket](/storage/minio/readme.md)

### Install and configure OADP Operator

* Install OADP Operator:
  ```
  export CHANNEL_NAME="stable-1.3"
  export CATALOG_SOURCE_NAME="redhat-operators"
  curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/backup-and-restore/oadp/01-operator.yaml | envsubst | oc apply -f -

  sleep 6

  oc patch installplan $(oc get ip -n openshift-adp  -o=jsonpath='{.items[?(@.spec.approved==false)].metadata.name}') -n openshift-adp --type merge --patch '{"spec":{"approved":true}}'

  oc get po -n openshift-adp
  NAME                                               READY   STATUS    RESTARTS   AGE
  openshift-adp-controller-manager-7f6f5fcf6-ndxcn   1/1     Running   0          89s
  ```

* Create a Secret named "cloud-credentials" in the openshift-adp project to allow access to Minio:
  ```
  cat << EOF > /root/credentials-velero
  [default]
  aws_access_key_id=minioadmin
  aws_secret_access_key=minioadmin
  EOF

  oc create secret generic cloud-credentials -n openshift-adp --from-file cloud=/root/credentials-velero
  ```

* Create DataProtectionApplication:
  ```
  export S3URL=$(oc get route minio -n minio -o jsonpath='http://{.spec.host}')
  export BUCKET_NAME="oadp-bucket"
  
  curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/backup-and-restore/oadp/02-dpa.yaml | envsubst | oc apply -f -
  ```

* View the Resources related to the DataProtectionApplication object:
  ```
  oc get po -n openshift-adp
  NAME                                               READY   STATUS    RESTARTS   AGE
  node-agent-ctzm4                                   1/1     Running   0          12s
  openshift-adp-controller-manager-7f6f5fcf6-ndxcn   1/1     Running   0          87m
  velero-7bb45ff59b-ntnpg                            1/1     Running   0          12s

  oc get dataprotectionapplication -n openshift-adp
  NAME         AGE
  dpa-sample   24s

  oc get backupStorageLocations -n openshift-adp
  NAME           PHASE       LAST VALIDATED   AGE   DEFAULT
  dpa-sample-1   Available   8s               38s   true
  
  velero get backup-locations -n openshift-adp
  NAME           PROVIDER   BUCKET/PREFIX        PHASE       LAST VALIDATED                  ACCESS MODE   DEFAULT
  dpa-sample-1   aws        oadp-bucket/velero   Available   2023-12-14 05:19:40 +0000 UTC   ReadWrite     true
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
  
  velero get backup -n openshift-adp
  NAME            STATUS      ERRORS   WARNINGS   CREATED                         EXPIRES   STORAGE LOCATION   SELECTOR
  sample-backup   Completed   0        0          2023-12-14 05:26:05 +0000 UTC   29d       dpa-sample-1       <none>
  ```

* Verify whether there is backup data in "my minio/ocp backup/velo/backups/sample backup":
  ```
  mc ls my-minio/oadp-bucket/velero/backups/sample-backup
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
  
  velero get restore -n openshift-adp
  NAME             BACKUP          STATUS      STARTED                         COMPLETED                       ERRORS   WARNINGS   CREATED                         SELECTOR
  sample-restore   sample-backup   Completed   2023-12-14 05:35:15 +0000 UTC   2023-12-14 05:35:53 +0000 UTC   0        11         2023-12-14 05:35:15 +0000 UTC   <none>
  ```

* Verify that the backup resources have been restored by entering the following command:
  ```
  oc get all -n sample-backup
  NAME                         READY   STATUS    RESTARTS   AGE
  pod/nginx-7c5fc86c75-qblm9   1/1     Running   0          75s
  
  NAME            TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)    AGE
  service/nginx   ClusterIP   172.30.25.116   <none>        8080/TCP   74s
  
  NAME                    READY   UP-TO-DATE   AVAILABLE   AGE
  deployment.apps/nginx   1/1     1            1           74s
  
  NAME                               DESIRED   CURRENT   READY   AGE
  replicaset.apps/nginx-7c5fc86c75   1         1         1       74s
  
  NAME                                   IMAGE REPOSITORY                                                       TAGS   UPDATED
  imagestream.image.openshift.io/nginx   image-registry.openshift-image-registry.svc:5000/sample-backup/nginx   v1.0   About a minute ago
  
  NAME                             HOST/PORT                     PATH   SERVICES   PORT       TERMINATION   WILDCARD
  route.route.openshift.io/nginx   nginx.apps.ocp4.example.com          nginx      8080-tcp                 None
  
  oc get pvc -n sample-backup
  NAME            STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS          AGE
  nginx-storage   Bound    pvc-54fd07f8-f6e0-4e79-b45a-cfb22ff58140   5Gi        RWO            managed-nfs-storage   119s
  
  oc -n sample-backup rsh nginx-7c5fc86c75-qblm9 
  Defaulted container "nginx" out of: nginx, restic-wait (init)
  sh-4.4$ df -h /data
  Filesystem                                                                               Size  Used Avail Use% Mounted on
  10.74.251.171:/nfs/sample-backup-nginx-storage-pvc-54fd07f8-f6e0-4e79-b45a-cfb22ff58140  150G   62G   88G  42% /data
  sh-4.4$ cat /data/test 
  hello
  sh-4.4$ exit
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
