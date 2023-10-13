### Deploy Local Storage

* Set environment variables.  

  ```
  export PVC_TARGET_NAMESPACE="test"
  export PV_NAME="test-pv"
  export PVC_NAME="test-pvc"
  export STORAGE_SIZE="100Gi"
  export PV_NODE_NAME="worker01.ocp4.example.com"
  ```
  
* Deploy Local Storage
  ```

  curl | envsubst | oc apply -f -

  oc get sc
  oc get pvc -n ${NAMESPACE}
  ```
