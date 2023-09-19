### Install Red Hat Openshift Logging and elasticsearch operator

* Install the Operator using the default namespace.
  ~~~
  $ export CHANNEL="stable-5.6"
  $ curl https://raw.githubusercontent.com/pancongliang/openshift/main/operator/logging/deploy/elasticsearch/01_deploy_operator.yaml | envsubst | oc apply -f -

  $ INSTALLPLAN_NAME_1=$(oc -n openshift-operators-redhat get installplans -o custom-columns=:metadata.name --no-headers)
  $ INSTALLPLAN_NAME_2=$(oc -n openshift-logging get installplans -o custom-columns=:metadata.name --no-headers)
  $ oc -n openshift-operators-redhat patch installplan $INSTALLPLAN_NAME_1 -p '{"spec":{"approved":true}}' --type merge
  $ oc -n openshift-logging patch installplan $INSTALLPLAN_NAME_2 -p '{"spec":{"approved":true}}' --type merge
  ~~~
  

### Install and configure Loki Stack resource

* Deploy [NFS Storage Class](https://github.com/pancongliang/openshift/edit/main/storage/nfs_storageclass/readme.md)

* Create ClusterLogging instance
  ~~~
  $ export STORAGECLASS_NAME="managed-nfs-storage"
  $ curl https://raw.githubusercontent.com/pancongliang/openshift/main/operator/logging/deploy/elasticsearch/02_deploy_instance.yaml | envsubst | oc apply -f -
  ~~~