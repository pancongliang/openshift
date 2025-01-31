cat << EOF > find-secondary-device.sh
#!/bin/bash
set -e
NODE_NAME=\$(hostname) && DEVICE_FOUND=false && COUNTER=\$1
for device in /dev/$DEVICE; do
  if ! blkid "\$device" &>/dev/null; then
    mkfs.xfs -f "\$device" &>/dev/null
    UUID=\$(blkid "\$device" -o value -s UUID 2>/dev/null)
    if [ -n "\$UUID" ]; then
      DEVICE_PATH="/dev/disk/by-uuid/\$UUID"
      echo "\$NODE_NAME: \$DEVICE_PATH" && echo "export DEVICE_PATH_\$COUNTER=\$DEVICE_PATH"
      DEVICE_FOUND=true 
      COUNTER=\$((COUNTER + 1))
    fi
  fi
done

if [ "\$DEVICE_FOUND" = false ]; then
  echo "\$NODE_NAME: - Couldn't find secondary block device!" >&2
fi
EOF


NODES=$(oc get nodes -l 'node-role.kubernetes.io/worker' -o=jsonpath='{.items[*].metadata.name}')

COUNTER=1

for node in $NODES; do
  ssh core@$node "sudo bash -s $COUNTER" < find-secondary-device.sh
  COUNTER=$(($COUNTER + 1))
done
