
## Installing the Local Storage Operator

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
cat << EOF > find-secondary-device.sh
#!/bin/bash
set -e
NODE_NAME=\$(hostname)
for device in /dev/$DEVICE; do
  if ! blkid "\$device" &>/dev/null; then
    mkfs.xfs -f "\$device" &>/dev/null
    UUID=\$(blkid "\$device" -o value -s UUID 2>/dev/null)
    [ -n "\$UUID" ] && echo "\$NODE_NAME: /dev/disk/by-uuid/\$UUID" && exit
  fi
done
echo "\$NODE_NAME: - Couldn't find secondary block device!" >&2
EOF

NODES=$(oc get nodes -l 'node-role.kubernetes.io/worker' -o=jsonpath='{.items[*].metadata.name}')
for node in $NODES; do ssh core@$node "sudo bash -s" < find-secondary-device.sh; done
```

3. **Store the device path**
```
export DEVICE_PATH_1=/dev/disk/by-uuid/59940ed2-51dd-4926-a997-9f037b5beb21
# Define the variable if it exists, otherwise skip it
export DEVICE_PATH_2=/dev/disk/by-uuid/a6113307-b4f1-43fd-86de-4b0fe34de98b
export DEVICE_PATH_3=/dev/disk/by-uuid/a08fc4c9-fd2d-4c0c-baef-d9d343db282e
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
