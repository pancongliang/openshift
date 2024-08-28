## Deploy NFS StorageClass


### Set necessary parameters
* Set necessary parameters
  ```
  export NAMESPACE="nfs-client-provisioner"
  export NFS_SERVER_IP="10.184.134.128"
  export NFS_DIR="/nfs"
  ```

### Install and configure the NFS server
* Install and configure the NFS server, skip this step if installed.
  ```
  wget -q https://raw.githubusercontent.com/pancongliang/openshift/main/storage/nfs-storageclass/01-install-nfs-package.sh
  
  source 01-install-nfs-package.sh
  ```

### Deploy NFS StorageClass
* Deploy NFS StorageClass via script
  ```
  wget -q https://raw.githubusercontent.com/pancongliang/openshift/main/storage/nfs-storageclass/02-deploy-nfs-storageclass.sh

  source 02-deploy-nfs-storageclass.sh

  oc get sc
  ```
  
### Test mount
* Deploy app and mount nfs sc
  ```
  oc new-app --name nginx --docker-image quay.io/redhattraining/hello-world-nginx:v1.0

  oc set volumes deployment/nginx \
     --add --name mysql-storage --type pvc --claim-class managed-nfs-storage \
     --claim-mode RWX --claim-size 5Gi --mount-path /usr/share/nginx/html \
     --claim-name test-volume
  ```
