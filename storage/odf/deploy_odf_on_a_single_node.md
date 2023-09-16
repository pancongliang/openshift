### This installation uses nfs storageClass as the backend storage of odf 

#### Install OpenShift Data Foundation in the web console
* Install the operator into the default namespace

#### Create and configure Noobaa object
* The backend storage uses StorageClass. If not, please refer to [Install NFS StorageClass](https://github.com/pancongliang/openshift/blob/main/storage/nfs_storageclass/readme.md)
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
  dbStorageClass: managed-nfs-storage
  dbType: postgres
  coreResources:
    requests:
      cpu: '0.1'
      memory: 1Gi
EOF
~~~

2. Create BackingStore object
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
csi-addons-controller-manager-7df4b4787b-rf77z     2/2     Running   0          9m
noobaa-core-0                                      1/1     Running   0          3m53s
noobaa-db-pg-0                                     1/1     Running   0          3m53s
noobaa-endpoint-c6944f-t99c4                       1/1     Running   0          2m56s
noobaa-operator-5479989f55-hxjnp                   1/1     Running   0          10m
noobaa-pv-backing-store-noobaa-pod-050fa690        1/1     Running   0          2m52s
noobaa-pv-backing-store-noobaa-pod-57f6c3e8        1/1     Running   0          2m52s
ocs-metrics-exporter-5f6c474855-lqtdm              1/1     Running   0          10m
ocs-operator-7947c989d5-qqbkv                      1/1     Running   0          10m
odf-console-6fd77c5bc8-8mz25                       1/1     Running   0          10m
odf-operator-controller-manager-5dcdd7586d-wxxlj   2/2     Running   0          10m
rook-ceph-operator-55fb8fb977-qwskn                1/1     Running   0          10m

$ oc get storageclass openshift-storage.noobaa.io
NAME                          PROVISIONER                       RECLAIMPOLICY   VOLUMEBINDINGMODE   ALLOWVOLUMEEXPANSION   AGE
openshift-storage.noobaa.io   openshift-storage.noobaa.io/obc   Delete          Immediate           false                  3m8s

$ oc get pvc -n openshift-storage
NAME                                          STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS          AGE
db-noobaa-db-pg-0                             Bound    pvc-d1105b63-bd85-4af3-83c0-f2ea9d34d276   50Gi       RWO            managed-nfs-storage   5m51s
noobaa-pv-backing-store-noobaa-pvc-050fa690   Bound    pvc-9174a675-9acf-470c-a504-341d7dde255f   100Gi      RWO            managed-nfs-storage   4m50s
noobaa-pv-backing-store-noobaa-pvc-57f6c3e8   Bound    pvc-d057128b-daf1-41ec-8d47-31a0ffbe603e   100Gi      RWO            managed-nfs-storage   4m50s

$ oc get BackingStore -n openshift-storage
NAME                      TYPE      PHASE   AGE
noobaa-pv-backing-store   pv-pool   Ready   5m48s

$ oc get noobaa -n openshift-storage
NAME     MGMT-ENDPOINTS                   S3-ENDPOINTS                    IMAGE                                                                                                            PHASE         AGE
noobaa   ["https://10.74.251.58:31560"]   ["https://10.74.251.9:31142"]   registry.redhat.io/odf4/mcg-core-rhel8@sha256:09ff291587e3ea37ddcc18fe97c1ac9d457ee2744a2542e1c2ecf23f7e7ef92e   Configuring   6m37s

$ oc get bucketclass -n openshift-storage
NAME                          PLACEMENT                                                        NAMESPACEPOLICY   QUOTA   PHASE      AGE
noobaa-default-bucket-class   {"tiers":[{"backingStores":["noobaa-default-backing-store"]}]}                             Rejected   5m40s
~~~

5.Update the backingStores configuration used by the noobaa-default-bucket-class object
~~~
$ oc patch bucketclass noobaa-default-bucket-class --patch '{"spec":{"placementPolicy":{"tiers":[{"backingStores":["noobaa-pv-backing-store"]}]}}}' --type merge -n openshift-storage

$ oc get bucketclass -n openshift-storage
NAME                          PLACEMENT                                                   NAMESPACEPOLICY   QUOTA   PHASE   AGE
noobaa-default-bucket-class   {"tiers":[{"backingStores":["noobaa-pv-backing-store"]}]}                             Ready   6m24s
~~~

#### Create ObjectBucketClaim and Object Storage secret 
1. Create ObjectBucketClaim
~~~
$ NAMESPACE="openshift-logging"
$ OBC_NAME="loki-bucket-odf"
$ GENERATEBUCKETNAME="${OBC_NAME}"
$ OBJECTBUCKETNAME="obc-${NAMESPACE}-${OBC_NAME}"

$ cat << EOF | envsubst | oc apply -f -
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
  namespace: ${NAMESPACE}
spec:
  additionalConfig:
    bucketclass: noobaa-default-bucket-class
  generateBucketName: ${GENERATEBUCKETNAME}
  objectBucketName: ${OBJECTBUCKETNAM}
  storageClassName: openshift-storage.noobaa.io
EOF
~~~

2. Create Object Storage secret
* Get bucket properties from the associated ConfigMap
~~~
$ BUCKET_HOST=$(oc get -n ${NAMESPACE} configmap ${OBC_NAME} -o jsonpath='{.data.BUCKET_HOST}')
$ BUCKET_NAME=$(oc get -n ${NAMESPACE} configmap ${OBC_NAME} -o jsonpath='{.data.BUCKET_NAME}')
$ BUCKET_PORT=$(oc get -n ${NAMESPACE} configmap ${OBC_NAME} -o jsonpath='{.data.BUCKET_PORT}')
~~~
* Get bucket access key from the associated Secret
~~~
$ ACCESS_KEY_ID=$(oc get -n ${NAMESPACE} secret ${OBC_NAME} -o jsonpath='{.data.AWS_ACCESS_KEY_ID}' | base64 -d)
$ SECRET_ACCESS_KEY=$(oc get -n ${NAMESPACE} secret ${OBC_NAME} -o jsonpath='{.data.AWS_SECRET_ACCESS_KEY}' | base64 -d)
~~~
* Create an Object Storage secret with keys as follows
~~~
$ oc create -n ${NAMESPACE} secret generic access-${OBC_NAME} \
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
