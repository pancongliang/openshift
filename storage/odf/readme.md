## Install and Configure ODF

### Install and Configure Local Storage Operator
- Use the [Local Storage Operator](https://github.com/pancongliang/openshift/blob/main/storage/local-sc/readme.md) to create a local volume in block mode.
- Ensure the OCP cluster has at least three worker nodes or infrastructure nodes, each with at least one 100GB disk.

### Install Red Hat OpenShift Data Foundation
- Install the Operator using the default namespace:
  ```
  export CHANNEL_NAME="stable-4.16"
  export CATALOG_SOURCE_NAME="redhat-operators"
  export NAMESPACE="openshift-storage"
  curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/storage/odf/01-operator.yaml | envsubst | oc create -f -
  curl -s https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/operator/approve_ip.sh | bash
  ```

### Label Nodes with Storage Devices
- Add the `ocs` label to OCP nodes with storage devices:
  ```
  oc get nodes -l 'node-role.kubernetes.io/worker' -o name | xargs -I {} oc label {} cluster.ocs.openshift.io/openshift-storage=''
  ```

### Create StorageCluster
- Create the StorageCluster by specifying variables:
  ```
  export LOCAL_PV_SIZE="100Gi"
  export STORAGE_CLASS_NAME="local-block"
  curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/storage/odf/02-storagecluster.yaml | envsubst | oc create -f -
  ```

### Verify Installation
- Check the status of ODF pods and storage classes:
  ```
  $ oc get pods -n openshift-storage
  NAME                                               READY   STATUS    RESTARTS   AGE
  csi-addons-controller-manager-75d5c79d45-twqrx     2/2     Running   0          9m1s
  csi-cephfsplugin-7ghqc                             2/2     Running   0          7m41s
  csi-cephfsplugin-bvdqf                             2/2     Running   0          7m41s
  csi-cephfsplugin-p5zrz                             2/2     Running   0          7m41s
  csi-cephfsplugin-provisioner-7478c8c75-skkb6       6/6     Running   0          7m41s
  csi-cephfsplugin-provisioner-7478c8c75-zdlgn       6/6     Running   0          7m41s
  csi-rbdplugin-7gjbk                                3/3     Running   0          7m41s
  csi-rbdplugin-provisioner-fbb8747c4-h8p5v          6/6     Running   0          7m41s
  csi-rbdplugin-provisioner-fbb8747c4-xfscv          6/6     Running   0          7m41s
  csi-rbdplugin-s8kkf                                3/3     Running   0          7m41s
  csi-rbdplugin-wtmjj                                3/3     Running   0          7m41s
  noobaa-operator-6474c9cc86-vw26h                   1/1     Running   0          9m6s
  ocs-operator-678456494-pxt2s                       1/1     Running   0          9m51s
  odf-console-77445df59f-9848j                       1/1     Running   0          9m6s
  odf-operator-controller-manager-86d8646ccc-nl2wh   2/2     Running   0          9m6s
  rook-ceph-mon-a-6b576d9bf5-fzhqr                   2/2     Running   0          7m32s
  rook-ceph-mon-b-5c9876d499-v6wqm                   2/2     Running   0          7m9s
  rook-ceph-mon-c-7dd6668dfd-5dzxf                   2/2     Running   0          113s
  rook-ceph-operator-644cf4f5f4-m8tjk                1/1     Running   0          9m19s
  ux-backend-server-7c7d688c8b-64qzm                 2/2     Running   0          9m51s

  $ oc get sc
  local-sc                      kubernetes.io/no-provisioner            Delete  WaitForFirstConsumer   false  7m16s
  ocs-storagecluster-ceph-rbd   openshift-storage.rbd.csi.ceph.com      Delete  Immediate              true  8m  # Block storage
  ocs-storagecluster-ceph-rgw   openshift-storage.ceph.rook.io/bucket   Delete  Immediate              false 9m  # RGW Object storage
  ocs-storagecluster-cephfs     openshift-storage.cephfs.csi.ceph.com   Delete  Immediate              true  8m  # FS storage
  openshift-storage.noobaa.io   openshift-storage.noobaa.io/obc         Delete  Immediate              false 8m  # NooBaa Object storage
  ```

### Verify ocs-storagecluster-cephfs storage class
- Use `ocs-storagecluster-cephfs` storage class to create a filesystem PVC and mount it:
  ```
  oc new-project test

  oc new-app --name nginx --docker-image quay.io/redhattraining/hello-world-nginx:v1.0

  oc set volumes deployment/nginx \
    --add --name nginx --type pvc --claim-class managed-nfs-storage \
    --claim-mode rwo --claim-size 5Gi --mount-path /usr/share/nginx/html --claim-name test-volume

  sleep 10
  
  oc -n test rsh $(oc get pods -n test -o=jsonpath='{.items[0].metadata.name}') df -h | grep '/usr'
  ```

### Create ObjectBucketClaim and Object Storage Secret
- Create an ObjectBucketClaim:
  ```
  export NAMESPACE="openshift-logging"
  export OBC_NAME="loki-bucket-odf"
  export GENERATE_BUCKET_NAME="${OBC_NAME}"
  export OBJECT_BUCKET_NAME="obc-${NAMESPACE}-${OBC_NAME}"
  curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/storage/odf/03-objectbucketclaim.yaml | envsubst | oc apply -f -
  ```

- Create an Object Storage secret:
  ```
  export BUCKET_HOST=$(oc get -n ${NAMESPACE} configmap ${OBC_NAME} -o jsonpath='{.data.BUCKET_HOST}')
  export BUCKET_NAME=$(oc get -n ${NAMESPACE} configmap ${OBC_NAME} -o jsonpath='{.data.BUCKET_NAME}')
  export BUCKET_PORT=$(oc get -n ${NAMESPACE} configmap ${OBC_NAME} -o jsonpath='{.data.BUCKET_PORT}')

  export ACCESS_KEY_ID=$(oc get -n ${NAMESPACE} secret ${OBC_NAME} -o jsonpath='{.data.AWS_ACCESS_KEY_ID}' | base64 -d)
  export SECRET_ACCESS_KEY=$(oc get -n ${NAMESPACE} secret ${OBC_NAME} -o jsonpath='{.data.AWS_SECRET_ACCESS_KEY}' | base64 -d)

  oc create -n ${NAMESPACE} secret generic ${OBC_NAME}-credentials     --from-literal=access_key_id="${ACCESS_KEY_ID}"     --from-literal=access_key_secret="${SECRET_ACCESS_KEY}"     --from-literal=bucketnames="${BUCKET_NAME}"     --from-literal=endpoint="https://${BUCKET_HOST}:${BUCKET_PORT}"
  ```

- Deploy LokiStack ClusterLogging and ClusterLogForwarder resources:
  ```
  export STORAGE_CLASS_NAME="ocs-storagecluster-cephfs"
  export BUCKET_NAME="${OBC_NAME}"
  curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/operator/logging/lokistack/03-deploy-loki-stack.yaml | envsubst | oc apply -f -
  ```
