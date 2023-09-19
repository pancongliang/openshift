### Install Red Hat Openshift Logging and elasticsearch operator

* Install the Operator using the default namespace.
  ~~~
  $ export CHANNEL="stable-5.6"
  $ curl https://raw.githubusercontent.com/pancongliang/openshift/main/operator/logging/deploy/elasticsearch/01_deploy_operator.yaml | envsubst | oc apply -f -
  ~~~

### Install and configure Loki Stack resource

* Deploy [NFS Storage Class](https://github.com/pancongliang/openshift/edit/main/storage/nfs_storageclass/readme.md)

* Create ClusterLogging instance
  ~~~
  $ export STORAGECLASS_NAME="managed-nfs-storage"
  $ curl https://raw.githubusercontent.com/pancongliang/openshift/main/operator/logging/deploy/elasticsearch/02_deploy_instance.yaml | envsubst | oc apply -f -
  ~~~
