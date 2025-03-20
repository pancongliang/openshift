## Provisioning Local Volumes Using the Local Storage Operator

### Install the Operator in the Default Namespace

```
export CHANNEL_NAME="stable"
export CATALOG_SOURCE_NAME="redhat-operators"
export NAMESPACE="openshift-local-storage"
curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/storage/local-sc/01-operator.yaml | envsubst | oc create -f -
curl -s https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/operator/approve_ip.sh | bash
```

### Add Disks to Worker Nodes

- Ensure that there are at least 3 worker nodes and each node has a minimum of 100GB of disk space if using ODF.
- Add labels to the worker nodes:

```
oc get nodes -l 'node-role.kubernetes.io/worker' -o name | xargs -I {} oc label {} local.storage.openshift.io/openshift-local-storage=''
```

### Find the newly added Disk Device Path in Node

**1. Run the script on the bastion machine to find the disk device path:**  
```
curl -sOL https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/storage/local-sc/discover-block-device.sh

sh discover-block-device.sh sd*
```

**2. Set device path variables, ensuring each path is unique. Skip if already set:**  
```
export DEVICE_PATH_1=/dev/disk/by-path/pci-0000:02:00.0-scsi-0:0:1:0

# Set only if not already defined
export DEVICE_PATH_2=/dev/disk/by-path/pci-0000:02:00.0-scsi-0:0:2:0
export DEVICE_PATH_3=/dev/disk/by-path/pci-0000:02:00.0-scsi-0:0:3:0
```  

### Create LocalVolume for Block and Filesystem Modes

**Block Volume Mode (ODF)**

```
oc create -f - <<EOF
apiVersion: "local.storage.openshift.io/v1"
kind: "LocalVolume"
metadata:
  name: "local-disk"
  namespace: "openshift-local-storage" 
spec:
  nodeSelector: 
    nodeSelectorTerms:
    - matchExpressions:
        - key: local.storage.openshift.io/openshift-local-storage
          operator: In
          values:
          - ""
  storageClassDevices:
    - storageClassName: "local-block" 
      forceWipeDevicesAndDestroyAllData: false
      volumeMode: Block 
      devicePaths: 
        - ${DEVICE_PATH_1}
        ${DEVICE_PATH_2:+- ${DEVICE_PATH_2}}
        ${DEVICE_PATH_3:+- ${DEVICE_PATH_3}}
EOF
```

**Filesystem Volume Mode**

```
oc create -f - <<EOF
apiVersion: "local.storage.openshift.io/v1"
kind: "LocalVolume"
metadata:
  name: "local-disk"
  namespace: "openshift-local-storage" 
spec:
  nodeSelector: 
    nodeSelectorTerms:
    - matchExpressions:
        - key: local.storage.openshift.io/openshift-local-storage
          operator: In
          values:
          - ""
  storageClassDevices:
    - storageClassName: "local-fs" 
      forceWipeDevicesAndDestroyAllData: false
      volumeMode: Filesystem
      fsType: xfs
      devicePaths:
        - ${DEVICE_PATH_1}
        ${DEVICE_PATH_2:+- ${DEVICE_PATH_2}}
        ${DEVICE_PATH_3:+- ${DEVICE_PATH_3}}
EOF
```

### Verify the Local Storage Status
```
oc get pods -n openshift-local-storage
oc get pv |grep local
oc get sc
```

### Uninstall Local Storage Operator
```
oc get localvolumes -n openshift-local-storage -o name | xargs -I {} oc -n openshift-local-storage delete {}
oc get localvolume -n openshift-local-storage -o jsonpath='{.items[*].metadata.name}' | xargs -I {} oc patch localvolume {} -n openshift-local-storage --type=json -p '[{"op": "remove", "path": "/metadata/finalizers"}]'

oc get pv | grep local | awk '{print $1}' | xargs -I {} oc delete pv {}
 
#!/bin/bash
for Hostname in $(oc get nodes -o jsonpath='{.items[*].status.addresses[?(@.type=="Hostname")].address}')
do
   echo "delete the /mnt/local-storage/ file in the $Hostname node"
   ssh -o StrictHostKeyChecking=no core@$Hostname sudo rm -rf /mnt/local-storage/*
done

export CHANNEL_NAME="stable"
export CATALOG_SOURCE_NAME="redhat-operators"
export NAMESPACE="openshift-local-storage"
curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/storage/local-sc/01-operator.yaml | envsubst | oc delete -f -
```


## Provisioning Local Volumes Without the Local Storage Operator

### Set the Required Parameters

```
export NAMESPACE="test"
export PV_NAME="test-pv"
export PVC_NAME="test-pvc"
export STORAGE_SIZE="100Gi"
export PV_NODE_NAME="worker01.ocp4.example.com"
```

### Deploy Local Storage PV/PVC

```
ssh core@${PV_NODE_NAME} sudo mkdir -p -m 777 /mnt/${PV_NAME}
curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/storage/local-sc/deploy-local-storage.yaml | envsubst | oc apply -f -
oc get sc
oc get pvc -n ${NAMESPACE}
```

### Test Volume Mount

```
oc new-app --name nginx --docker-image quay.io/redhattraining/hello-world-nginx:v1.0
oc set volumes deployment/nginx --add --name test-volume --type persistentVolumeClaim --claim-name ${PVC_NAME} --mount-path /usr/share/nginx/html

oc rsh nginx-d75558854-7575d
sh-4.4$ touch /usr/share/nginx/html/1

ssh core@${PV_NODE_NAME} sudo ls /mnt/test-pv/
1
```

