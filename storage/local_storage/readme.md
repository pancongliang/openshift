### Deploy Local Storage

* Set environment variables.  

  ```
  export PVC_TARGET_NAMESPACE="test"
  export PV_NAME="test-pv"
  export PVC_NAME="test-pvc"
  export STORAGE_SIZE="100Gi"
  ```
  
* Deploy Local Storage 
  curl | envsubst | oc apply -f -

  oc get sc
  oc get pvc -n ${NAMESPACE}
  ```
