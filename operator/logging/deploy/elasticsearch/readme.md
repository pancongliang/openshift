### Install Red Hat Openshift Logging and elasticsearch operator

* Install the Operator using the default namespace.
  ```
  export CHANNEL_NAME="stable-5.6"
  export CATALOG_SOURCE_NAME="redhat-operators"
  
  curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/operator/logging/deploy/elasticsearch/01_deploy_operator.yaml | envsubst | oc apply -f -

  oc patch installplan $(oc get ip -n openshift-operators-redhat  -o=jsonpath='{.items[?(@.spec.approved==false)].metadata.name}') -n openshift-operators-redhat --type merge --patch '{"spec":{"approved":true}}'
  oc patch installplan $(oc get ip -n openshift-logging  -o=jsonpath='{.items[?(@.spec.approved==false)].metadata.name}') -n openshift-logging --type merge --patch '{"spec":{"approved":true}}'
  ```
  

### Deploy ClusterLogging instance

* Deploy [NFS Storage Class](https://github.com/pancongliang/openshift/edit/main/storage/nfs_storageclass/readme.md)

* Create ClusterLogging instance
  ```
  export STORAGECLASS_NAME="managed-nfs-storage"
  
  curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/operator/logging/deploy/elasticsearch/02_deploy_instance.yaml | envsubst | oc apply -f -

  oc get po -n openshift-logging
  ```
