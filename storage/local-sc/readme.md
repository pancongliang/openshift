### Installing the Local Storage Operator

* Install the Operator using the default namespace
  ```
  export CHANNEL_NAME="stable"
  export CATALOG_SOURCE_NAME="redhat-operators"
  export NAMESPACE="openshift-local-storage"
  curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/storage/local-sc/01-operator.yaml | envsubst | oc create -f -
  curl -s https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/operator/approve_ip.sh | bash
  ```

### Automating discovery and provisioning for local storage devices

* Add disk to worker node(If used for ODF, need at least 3 worker nodes, add at least 100GB disk to each node, and then add labels)


* Add a label to the node where the disk is added
  ```
  export NODE_NAME01=worker01.ocp4.example.com
  oc label node ${NODE_NAME01} cluster.ocs.openshift.io/openshift-storage=''

  export NODE_NAME02=worker02.ocp4.example.com
  oc label node ${NODE_NAME02} cluster.ocs.openshift.io/openshift-storage=''

  export NODE_NAME03=worker03.ocp4.example.com
  oc label node ${NODE_NAME03} cluster.ocs.openshift.io/openshift-storage=''
  ```
  
* Create LocalVolumeDiscovery
  ```
  oc create -f https://raw.githubusercontent.com/pancongliang/openshift/main/storage/local-sc/02-localvolumediscovery.yaml

  oc get localvolumediscoveryresults -n openshift-local-storage
  ```  

* Create a LocalVolumeSet
  ```
  # Volume mode is "Block"(ODF)
  oc create -f https://raw.githubusercontent.com/pancongliang/openshift/main/storage/local-sc/03-localvolumeset-block.yaml

  # or

  # Volume mode is "FileSystem"
  export FSTYPE=xfs
  curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/storage/local-sc/03-localvolumeset-fs.yaml | envsubst | oc create -f -

  oc get pods -n openshift-local-storage | grep "diskmaker-manager"
  oc get pv -n openshift-local-storage
  oc get sc
  ```

  
