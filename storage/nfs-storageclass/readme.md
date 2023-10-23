## Deploy NFS StorageClass

* Set necessary parameters
  ```
  export NAMESPACE="nfs-client-provisioner"
  export NFS_SERVER_IP="10.74.251.171"
  export NFS_DIR="/nfs"
  ```

* Install and configure the NFS server, skip this step if installed.
  ```
  wget -s https://raw.githubusercontent.com/pancongliang/openshift/main/storage/nfs-storageclass/01-install-nfs-package.sh
  
  source 01-install-nfs-package.sh
  ```

* Deploy NFS StorageClass
  ```
  curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/storage/nfs-storageclass/02-deploy-nfs-storageclass.yaml | envsubst | oc apply -f -
  ```
