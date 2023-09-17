#### Deploy NFS StorageClass

* Set variables
  ~~~
  export NFS_NAMESPACE="nfs-client-provisioner"
  export NFS_SERVER_IP="10.74.251.171"
  export NFS_DIR="/nfs"
  ~~~

* Optional: Install and configure NFS server
  ~~~
  wget https://raw.githubusercontent.com/pancongliang/openshift/main/storage/nfs_storageclass/01_install_nfs_package.sh
  source 01_install_nfs_package.sh
  ~~~

* Deploy NFS StorageClass
  ~~~
  wget https://raw.githubusercontent.com/pancongliang/openshift/main/storage/nfs_storageclass/02_deploy_nfs_storageclass.sh
  source 02_deploy_nfs_storageclass.sh
  ~~~
