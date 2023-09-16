#### Install OpenShift Data Foundation in the web console
* Install the operator into the default namespace

#### Create and configure Noobaa object
1. Create Noobaa object
~~~
$ cat << EOF | oc apply -f -
apiVersion: noobaa.io/v1alpha1
kind: NooBaa
metadata:
  name: noobaa
  namespace: openshift-storage
spec:
 dbResources:
   requests:
     cpu: '0.1'
     memory: 1Gi
 dbType: postgres
 coreResources:
   requests:
     cpu: '0.1'
     memory: 1Gi
EOF
~~~

2. Create BackingStore object
* The backend storage uses StorageClass. If not, please refer to [Install NFS StorageClass](https://github.com/pancongliang/openshift/blob/main/storage/nfs_storageclass/readme.md)
~~~
$ cat << EOF | oc apply -f -
apiVersion: noobaa.io/v1alpha1
kind: BackingStore
metadata:
  finalizers:
  - noobaa.io/finalizer
  labels:
    app: noobaa
  name: noobaa-pv-backing-store
  namespace: openshift-storage
spec:
  pvPool:
    numVolumes: 2
    resources:
      requests:
        storage: 100Gi
    storageClass: managed-nfs-storage
  type: pv-pool
EOF
~~~

4.View related objects
~~~
$ oc get po -n openshift-storage
NAME                                               READY   STATUS    RESTARTS   AGE
csi-addons-controller-manager-748f67756d-sdw6t     2/2     Running   0          10m
noobaa-core-0                                      1/1     Running   0          2m1s
noobaa-db-pg-0                                     1/1     Running   0          2m1s
noobaa-endpoint-b45489b-kr6rj                      1/1     Running   0          29s
noobaa-operator-bdcf8977d-tqxsj                    1/1     Running   0          11m
noobaa-pv-backing-store-noobaa-pod-23f9a0f6        1/1     Running   0          7s
noobaa-pv-backing-store-noobaa-pod-f876724d        1/1     Running   0          7s
ocs-metrics-exporter-9c4586984-dmlx2               1/1     Running   0          11m
ocs-operator-566dccb78b-62xrt                      1/1     Running   0          11m
odf-console-65686c7d9f-hcdrj                       1/1     Running   0          11m
odf-operator-controller-manager-84b6b455d5-t5nnl   2/2     Running   0          11m
rook-ceph-operator-6fc75fc489-8j7sz                1/1     Running   0          11m

$ oc get storageclass openshift-storage.noobaa.io
NAME                          PROVISIONER                       RECLAIMPOLICY   VOLUMEBINDINGMODE   ALLOWVOLUMEEXPANSION   AGE
openshift-storage.noobaa.io   openshift-storage.noobaa.io/obc   Delete          Immediate           false                  38s

$ oc get pvc -n openshift-storage
NAME                                               STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   AGE
db-noobaa-db-pg-0                                  Bound    pvc-914e1b77-1aed-46a8-aa8c-062529449a97   50Gi       RWO            nfs-storage    2m48s
noobaa-default-backing-store-noobaa-pvc-dd3ef018   Bound    pvc-ca2ac57f-4aaa-48b3-947d-587869407ba2   50Gi       RWO            nfs-storage    44s
noobaa-pv-backing-store-noobaa-pvc-23f9a0f6        Bound    pvc-1dc6ebdc-5eb3-4da4-adae-171bfd22a8f4   100Gi      RWO            nfs-storage    55s
noobaa-pv-backing-store-noobaa-pvc-f876724d        Bound    pvc-07216e39-5989-470c-8014-a29224bb5026   100Gi      RWO            nfs-storage    54s

$ oc get BackingStore -n openshift-storage
NAME                           TYPE      PHASE   AGE
noobaa-default-backing-store   pv-pool   Ready   6m25s
noobaa-pv-backing-store        pv-pool   Ready   6m39s

$ oc get noobaa -n openshift-storage
NAME     MGMT-ENDPOINTS                    S3-ENDPOINTS                      IMAGE                                                                                                            PHASE   AGE
noobaa   ["https://10.74.249.234:31440"]   ["https://10.74.249.234:30856"]   registry.redhat.io/odf4/mcg-core-rhel8@sha256:3261f399d8cf9ad6311eceaba78454ebad17f34d98811745484e618d568f93ff   Ready   8m42s

$ oc get bucketclass -n openshift-storage
NAME                          PLACEMENT                                                        NAMESPACEPOLICY   QUOTA   PHASE   AGE
noobaa-default-bucket-class   {"tiers":[{"backingStores":["noobaa-default-backing-store"]}]}                             Ready   7m1s
~~~


5.Update the backingStores configuration used by the noobaa-default-bucket-class object
~~~
$ oc patch bucketclass noobaa-default-bucket-class --patch '{"spec":{"placementPolicy":{"tiers":[{"backingStores":["noobaa-pv-backing-store"]}]}}}' --type merge -n openshift-storage
~~~

#### Create ObjectBucketClaim and Object Storage secret 
1. Create ObjectBucketClaim
~~~
$ NAMESPACE="openshift-logging"
$ OBC_NAME="loki-bucket-odf"
$ GENERATEBUCKETNAME="loki-bucket-odf"
$ OBJECTBUCKETNAME="obc-openshift-logging-loki-bucket-odf"

$ cat << EOF | oc apply -f -
apiVersion: objectbucket.io/v1alpha1
kind: ObjectBucketClaim
metadata:
  finalizers:
  - objectbucket.io/finalizer
  labels:
    app: noobaa
    bucket-provisioner: openshift-storage.noobaa.io-obc
    noobaa-domain: openshift-storage.noobaa.io
  name: ${OBC_NAME}
  namespace: ${NAMESPACE}            # Specify the namespace using bucket object
spec:
  additionalConfig:
    bucketclass: noobaa-default-bucket-class
  generateBucketName: ${GENERATEBUCKETNAME}     # Specify bucket name
  objectBucketName: ${OBJECTBUCKETNAM}
  storageClassName: openshift-storage.noobaa.io
EOF
~~~

2. Create Object Storage secret
* Get bucket properties from the associated ConfigMap
~~~
$ BUCKET_HOST=$(oc get -n openshift-logging configmap loki-bucket-odf -o jsonpath='{.data.BUCKET_HOST}')
$ BUCKET_NAME=$(oc get -n openshift-logging configmap loki-bucket-odf -o jsonpath='{.data.BUCKET_NAME}')
$ BUCKET_PORT=$(oc get -n openshift-logging configmap loki-bucket-odf -o jsonpath='{.data.BUCKET_PORT}')
~~~
* Get bucket access key from the associated Secret
~~~
$ ACCESS_KEY_ID=$(oc get -n openshift-logging secret loki-bucket-odf -o jsonpath='{.data.AWS_ACCESS_KEY_ID}' | base64 -d)
$ SECRET_ACCESS_KEY=$(oc get -n openshift-logging secret loki-bucket-odf -o jsonpath='{.data.AWS_SECRET_ACCESS_KEY}' | base64 -d)
~~~
* Create an Object Storage secret with keys as follows
~~~
$ oc create -n openshift-logging secret generic lokistack-dev-odf \
   --from-literal=access_key_id="${ACCESS_KEY_ID}" \
   --from-literal=access_key_secret="${SECRET_ACCESS_KEY}" \
   --from-literal=bucketnames="${BUCKET_NAME}" \
   --from-literal=endpoint="https://${BUCKET_HOST}:${BUCKET_PORT}"
~~~

#### Create PVC/PV verification using ODF
~~~
$ oc new-app --name nginx --docker-image quay.io/redhattraining/hello-world-nginx:v1.0

$ oc set volumes deployment/nginx \
   --add --name nginx-volume --type pvc --claim-class openshift-storage.noobaa.io \
   --claim-mode RWO --claim-size 20Gi --mount-path /data \
   --claim-name nginx-volume

$ oc rsh nginx df -h data
~~~
