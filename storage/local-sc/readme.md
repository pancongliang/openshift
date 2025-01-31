
## Provisioning local volumes by using the Local Storage Operator

### Install the Operator using the default namespace

```
export CHANNEL_NAME="stable"
export CATALOG_SOURCE_NAME="redhat-operators"
export NAMESPACE="openshift-local-storage"
curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/storage/local-sc/01-operator.yaml | envsubst | oc create -f -
curl -s https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/operator/approve_ip.sh | bash
```

### Add Disk to worker node

- If used for ODF, ensure at least 3 worker nodes and at least 100GB disk on each node.
- Add labels to the nodes:

```
oc get nodes -l 'node-role.kubernetes.io/worker' -o name | xargs -I {} oc label {} local.storage.openshift.io/openshift-local-storage=''
```

### Check Node Disk Device Path

1. **Set the device variable**
```
export DEVICE='sd*'
```

2. **Check node disk device path through script**
```
https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/storage/local-sc/find-secondary-device.sh
bash find-secondary-uuid.sh
```

3. **Store the device path**
```
export DEVICE_PATH_1=/dev/disk/by-path/pci-0000:02:00.0-scsi-0:0:1:0
# Define the variable if it exists, otherwise skip it
export DEVICE_PATH_2=/dev/disk/by-path/pci-0000:02:00.0-scsi-0:0:2:0
export DEVICE_PATH_3=/dev/disk/by-path/pci-0000:02:00.0-scsi-0:0:3:0
``` 

### Create LocalVolume

#### For Block Volume Mode(ODF)

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

#### For Filesystem Volume Mode

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

## Check Local Storage

```bash
oc get pods -n openshift-local-storage
oc get pv -n openshift-local-storage
oc get sc
```



## Provisioning local volumes without the Local Storage Operator
* Set necessary parameters

  ```
  export NAMESPACE="test"
  export PV_NAME="test-pv"
  export PVC_NAME="test-pvc"
  export STORAGE_SIZE="100Gi"
  export PV_NODE_NAME="worker01.ocp4.example.com"
  ```
  
* Deploy Local Storage PV/PVC
  ```
  ssh core@${PV_NODE_NAME} sudo mkdir -p -m 777 /mnt/${PV_NAME}
  
  curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/storage/local-storage/deploy-local-storage.yaml | envsubst | oc apply -f -

  oc get sc
  oc get pvc -n ${NAMESPACE}
  ```

* Test mount
  ```
  oc new-app --name nginx --docker-image quay.io/redhattraining/hello-world-nginx:v1.0
  oc set volumes deployment/nginx --add --name test-volume \
     --type persistentVolumeClaim --claim-name ${PVC_NAME} --mount-path /usr/share/nginx/html

  oc rsh nginx-d75558854-7575d
  sh-4.4$ touch /usr/share/nginx/html/1

  ssh core@${PV_NODE_NAME} sudo ls /mnt/test-pv/
  1
  ```

