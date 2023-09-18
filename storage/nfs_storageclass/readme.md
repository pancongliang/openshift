#### Deploy NFS StorageClass

* Set variables
  ~~~
  $ export NAMESPACE="nfs-client-provisioner"
  $ export NFS_SERVER_IP="10.74.251.171"
  $ export NFS_DIR="/nfs"
  ~~~

* Install and configure the NFS server, skip this step if installed.
  ~~~
  $ wget https://raw.githubusercontent.com/pancongliang/openshift/main/storage/nfs_storageclass/01_install_nfs_package.sh
  $ source 01_install_nfs_package.sh
  ~~~

* Deploy NFS StorageClass
  ~~~
  $ curl https://raw.githubusercontent.com/pancongliang/openshift/main/storage/nfs_storageclass/02_deploy_nfs_storageclass.yaml | envsubst | oc apply -f -
  $ oc adm policy add-scc-to-user hostmount-anyuid system:serviceaccount:${NFS_NAMESPACE}:nfs-client-provisioner
  ~~~
