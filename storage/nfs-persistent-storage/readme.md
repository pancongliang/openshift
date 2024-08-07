## Deploy NFS Persistent Storage

* Set necessary parameters

  ```
  export NFS_SERVER_IP="10.74.251.171"
  export NFS_DIR="/nfs"
  export PV_NAME="test-pv"
  export PVC_NAME="test-pvc"
  export STORAGE_SIZE="10Gi"
  exportACCESS_MODE=ReadWriteMany
  ```
  
* Deploy NFS Persistent Storage
  ```
  curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/storage/nfs-persistent-storage/nfs-persistent-storage.yaml | envsubst | oc apply -f -

  oc get pv
  oc get pvc
  ```
