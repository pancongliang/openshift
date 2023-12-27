## Deploy NFS StorageClass

* Set necessary parameters
  ```
  export NAMESPACE="nfs-client-provisioner"
  export NFS_SERVER_IP="10.74.251.171"
  export NFS_DIR="/nfs"
  ```

* Install and configure the NFS server, skip this step if installed.
  ```
  wget -q https://raw.githubusercontent.com/pancongliang/openshift/main/storage/nfs-storageclass/01-install-nfs-package.sh
  
  source 01-install-nfs-package.sh
  ```

* Deploy NFS StorageClass via script
  ```
  wget -q https://raw.githubusercontent.com/pancongliang/openshift/main/storage/nfs-storageclass/02-deploy-nfs-storageclass.sh

  source 02-deploy-nfs-storageclass.sh
  ```
  
* Or deploy NFS StorageClass via yaml
  ```
  curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/storage/nfs-storageclass/02-rbac.yaml | envsubst | oc apply -f -
  oc adm policy add-scc-to-user hostmount-anyuid system:serviceaccount:${NAMESPACE}:nfs-client-provisioner
  curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/storage/nfs-storageclass/03-deployment.yaml | envsubst | oc apply -f -
  curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/storage/nfs-storageclass/04-class.yaml | envsubst | oc apply -f -
  ```
