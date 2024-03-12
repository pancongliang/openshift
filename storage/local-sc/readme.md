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

### Automating discovery and provisioning for local storage devices

* Add disk to worker node

* Create LocalVolumeDiscovery
  ```
  oc create -f https://raw.githubusercontent.com/pancongliang/openshift/main/storage/local-sc/02-localvolumediscovery.yaml
  ```  

* Create a LocalVolumeSet
  ```
  # Volume mode is "Block"(ODF)
  oc create -f https://raw.githubusercontent.com/pancongliang/openshift/main/storage/local-sc/03-localvolumeset-block.yaml

  # or

  # Volume mode is "FileSystem"
  export FSTYPE=xfs
  curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/storage/local-sc/03-localvolumeset-fs.yaml | envsubst | oc create -f -
  ```

  
