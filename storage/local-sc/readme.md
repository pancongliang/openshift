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
  oc get nodes -l 'node-role.kubernetes.io/worker' -o name | xargs -I {} oc label {} cluster.ocs.openshift.io/openshift-storage=''
  ```

* Check node disk uuid
  ```
  export DEVICE='sd*'
  
  cat << 'EOF' > find-secondary-device.sh
  #!/bin/bash
  set -uo pipefail
  
  for device in /dev/sd*; do
    /usr/sbin/blkid "${device}" &> /dev/null
    if [ $? == 2 ]; then
      ls -l /dev/disk/by-path/ | awk -v dev="${device##*/}" '$0 ~ dev {print "/dev/disk/by-path/" $9}'
      exit
    fi
  done
  echo "Couldn't find secondary block device!" >&2
  EOF
  
  NODES=$(oc get nodes -l 'node-role.kubernetes.io/worker' -o=jsonpath='{.items[*].metadata.name}')
  for node in $NODES; do ssh core@$node "sudo bash -s" < find-secondary-device.sh; done

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

  
