
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
set -uo pipefail
NODE_NAME="\$(hostname)"
DEVICE_PATH=""
for device in /dev/$DEVICE; do
  /usr/sbin/blkid "\${device}" &> /dev/null
  if [ \$? == 2 ]; then
    mkfs.xfs -f "\${device}" &> /dev/null
    UUID=\$(blkid "\${device}" -o value -s UUID 2>/dev/null)
    if [ -n "\$UUID" ]; then
      DEVICE_PATH="/dev/disk/by-uuid/\$UUID"
      echo "\$NODE_NAME:  \$DEVICE_PATH"
      exit
    fi
  fi
done
echo "\$NODE_NAME:  - Couldn't find secondary block device!" >&2
EOF

NODES=$(oc get nodes -l 'node-role.kubernetes.io/worker' -o=jsonpath='{.items[*].metadata.name}')
for node in $NODES; do ssh core@$node "sudo bash -s" < find-secondary-device.sh; done
```

3. **Store the device path**
```
export DEVICE_PATH_1=/dev/disk/by-uuid/eb74ce65-06ac-4aeb-8fa1-e060281fc14e

# Define the variable if it exists, otherwise skip it
export DEVICE_PATH_2=/dev/disk/by-uuid/5b9e314b-1861-440a-8b3f-89fcdbc73dcb
export DEVICE_PATH_3=/dev/disk/by-uuid/7d606cd3-a9a5-4c12-9713-d308964a4496
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
    - storageClassName: "local-sc"
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
    - storageClassName: "local-sc"
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
