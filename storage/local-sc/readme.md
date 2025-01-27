
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
oc get nodes -l 'node-role.kubernetes.io/worker' -o name | xargs -I {} oc label {} cluster.ocs.openshift.io/openshift-storage=''
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

for device in /dev/$DEVICE; do
  /usr/sbin/blkid "\${device}" &> /dev/null
  if [ \$? == 2 ]; then
    ls -l /dev/disk/by-path/ | awk -v dev="\${device##*/}" '\$0 ~ dev {print "/dev/disk/by-path/" \$9}'
    exit
  fi
done
echo "Couldn't find secondary block device!" >&2
EOF

NODES=$(oc get nodes -l 'node-role.kubernetes.io/worker' -o=jsonpath='{.items[*].metadata.name}')
for node in $NODES; do ssh core@$node "sudo bash -s" < find-secondary-device.sh; done
```

3. **Store the device path**
```
export DEVICE_PATH=/dev/disk/by-path/pci-0000:02:00.0-scsi-0:0:1:0
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
          - key: cluster.ocs.openshift.io/openshift-storage
            operator: In
            values:
              - ""
  storageClassDevices:
    - storageClassName: "localblock"
      forceWipeDevicesAndDestroyAllData: false
      volumeMode: Block
      devicePaths:
        - ${DEVICE_PATH}
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
          - key: cluster.ocs.openshift.io/openshift-storage
            operator: In
            values:
              - ""
  storageClassDevices:
    - storageClassName: "local-sc"
      forceWipeDevicesAndDestroyAllData: false
      volumeMode: Filesystem
      fsType: xfs
      devicePaths:
        - ${DEVICE_PATH}
EOF
```

## Check Local Storage

```bash
oc get pods -n openshift-local-storage
oc get pv -n openshift-local-storage
oc get sc
```
