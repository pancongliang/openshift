### Install Red Hat Openshift Logging and elasticsearch operator in the console

* Install the Operator using the default namespace.


### Install and configure Loki Stack resource

* Deploy [NFS Storage Class](https://github.com/pancongliang/openshift/edit/main/storage/nfs_storageclass/readme.md)

* Create ClusterLogging instance
  ~~~
  $ export STORAGECLASS_NAME="managed-nfs-storage"
  $ curl https://raw.githubusercontent.com/pancongliang/openshift/main/operator/logging/deploy/elasticsearch/instance.yaml | envsubst | oc apply -f -
  ~~~
