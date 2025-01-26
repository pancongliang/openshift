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
  export NODE_NAME02=worker02.ocp4.example.com
  export NODE_NAME03=worker03.ocp4.example.com
  
  oc label node ${NODE_NAME01} cluster.ocs.openshift.io/openshift-storage=''
  oc label node ${NODE_NAME02} cluster.ocs.openshift.io/openshift-storage=''
  oc label node ${NODE_NAME03} cluster.ocs.openshift.io/openshift-storage=''
  ```

* Check node disk uuid
  ```
  ssh core@${NODE_NAME01} sudu ls -ltr /dev/disk/by-path/
  ssh core@${NODE_NAME02} sudu ls -ltr /dev/disk/by-path/
  ssh core@${NODE_NAME03} sudu ls -ltr /dev/disk/by-path/

  export UUID=/dev/disk/by-path/pci-0000:02:00.0-scsi-0:0:1:0
  ```

  
* Create LocalVolume 
  ```
  export VOLUME_MODE=Block
  # export VOLUME_MODE=Filesystem
  
  oc create -f - <<EOF
  apiVersion: "local.storage.openshift.io/v1"
  kind: "LocalVolume"
  metadata:
    name: "local-disks"
    namespace: "openshift-local-storage" 
  spec:
    nodeSelector:
      nodeSelectorTerms:
        - matchExpressions:
            - key: cluster.ocs.openshift.io/openshift-storage
              operator: In
              values:
                - ""
    storageClassDevices:
      - storageClassName: "localblock" 
        forceWipeDevicesAndDestroyAllData: false 
        volumeMode: ${VOLUME_MODE} 
        devicePaths: 
          - ${UUID}
  EOF
  ```

* Create LocalVolume
  ```
  oc create -f - <<EOF
  apiVersion: "local.storage.openshift.io/v1"
  kind: "LocalVolume"
  metadata:
    name: "local-disks"
    namespace: "openshift-local-storage" 
  spec:
    nodeSelector:
      nodeSelectorTerms:
        - matchExpressions:
            - key: cluster.ocs.openshift.io/openshift-storage
              operator: In
              values:
                - ""
    storageClassDevices:
      - storageClassName: "localblock" 
        forceWipeDevicesAndDestroyAllData: false 
        volumeMode: Block 
        devicePaths: 
          - ${UUID}
  EOF
  ``` 
   

* Check local storage
  ```
  oc get pods -n openshift-local-storage
  oc get pv -n openshift-local-storage
  oc get sc
  ```

  
