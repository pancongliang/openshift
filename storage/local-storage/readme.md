## Deploy Local Storage

* Set necessary parameters

  ```
  export PVC_TARGET_NAMESPACE="test"
  export PV_NAME="test-pv"
  export PVC_NAME="test-pvc"
  export STORAGE_SIZE="100Gi"
  export PV_NODE_NAME="worker01.ocp4.example.com"
  ```
  
* Deploy Local Storage
  ```
  ssh core@${PV_NODE_NAME} sudo mkdir -p -m 777 /mnt/${PV_NAME}
  
  curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/storage/local-storage/deploy-local-storage.yaml | envsubst | oc apply -f -

  oc get sc
  oc get pvc -n ${NAMESPACE}
  ```
