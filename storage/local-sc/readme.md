### Installing the Local Storage Operator

* Install the Operator using the default namespace
  ```
  export CHANNEL_NAME="stable"
  export CATALOG_SOURCE_NAME="redhat-operators"
  curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/storage/local-sc/01-operator.yaml | envsubst | oc create -f -

  sleep 6
  
  oc patch installplan $(oc get ip -n openshift-local-storage  -o=jsonpath='{.items[?(@.spec.approved==false)].metadata.name}') -n openshift-local-storage --type merge --patch '{"spec":{"approved":true}}'

  oc get ip -n openshift-local-storage
  ```

### Provisioning local volumes by using the Local Storage Operator

* 
