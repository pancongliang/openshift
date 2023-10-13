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
  export NFS_PATH="/nfs/pv005"
  export NFS_IP="10.74.251.171"
  
  curl https://raw.githubusercontent.com/pancongliang/openshift/main/operator/rhsso/02_create_keycloak_pv.yaml | envsubst | oc apply -f -
  ```
  
* Create Keycloak
  ```
  curl https://raw.githubusercontent.com/pancongliang/openshift/main/operator/rhsso/02_create_keycloak.yaml | envsubst | oc apply -f -
  ```

### Configuring the Red Hat Single Sign-On Operator

* Create realm custom resource
  ```
  export USER_NAME=rhadmin
  export PASSWORD=redhat
  
  curl https://raw.githubusercontent.com/pancongliang/openshift/main/operator/rhsso/03_create_keycloak_realm.yaml | envsubst | oc apply -f -
  ```
* Create client custom resource
  ```
  export OAUTH_HOST=$(oc get route oauth-openshift -n openshift-authentication --template='{{.spec.host}}')
  export CONSOLE_HOST=$(oc get route console -n openshift-console --template='{{.spec.host}}')
  
  curl https://raw.githubusercontent.com/pancongliang/openshift/main/operator/rhsso/04_create_keycloak_client.yaml | envsubst | oc apply -f -
  ```
* Create RH-SSO user
  ```
  curl https://raw.githubusercontent.com/pancongliang/openshift/main/operator/rhsso/05_create_keycloak_user.yaml | envsubst | oc apply -f -
  ```



