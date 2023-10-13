### Installing the Red Hat Single Sign-On Operator on a cluster

* Installing RHSSO Operator from the command line
  ```
  export NAMESPACE=rhsso
  export CHANNEL="stable"
  export CATALOG_SOURCE_NAME="redhat-operators"
  
  curl https://raw.githubusercontent.com/pancongliang/openshift/main/operator/rhsso/01_deploy_operator.yaml | envsubst | oc apply -f -

  oc patch installplan $(oc get ip -n ${NAMESPACE} -o=jsonpath='{.items[?(@.spec.approved==false)].metadata.name}') -n ${NAMESPACE} --type merge --patch '{"spec":{"approved":true}}'
  ```

### Create Keycloak custom resources

* Create pv with size 1GB or deploy [NFS Storage Class](https://github.com/pancongliang/openshift/edit/main/storage/nfs_storageclass/readme.md),The following is an example of nfs pv
  
  ```
  export NFS_PATH="/nfs/pv002"
  export NFS_IP="10.74.251.171"
  
  curl https://raw.githubusercontent.com/pancongliang/openshift/main/operator/rhsso/02_create_keycloak_pv.yaml | envsubst | oc apply -f -
  ```
  
* Create Keycloak
  ```
  oc create -f https://raw.githubusercontent.com/pancongliang/openshift/main/operator/rhsso/02_create_keycloak.yaml
  ```

### Configuring the Red Hat Single Sign-On Operator

* Create realm custom resource

* Create client custom resource

* Create user custom resource

* Deploy [NFS Storage Class](https://github.com/pancongliang/openshift/edit/main/storage/nfs_storageclass/readme.md)

* Create ClusterLogging instance
  ```
  export STORAGECLASS_NAME="managed-nfs-storage"
  
  curl https://raw.githubusercontent.com/pancongliang/openshift/main/operator/logging/deploy/elasticsearch/02_deploy_instance.yaml | envsubst | oc apply -f -

  oc get po -n openshift-logging
  ```

