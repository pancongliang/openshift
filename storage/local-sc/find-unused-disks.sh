#!/bin/bash

# Get CLI parameters and assign them to DEVICE
if [ $# -eq 0 ]; then
    echo "Usage: sh $0 <device name, e.g.: sd*>"
    exit 1
fi
DEVICE=$1


cat << EOF > find-secondary-device.sh
#!/bin/bash
set -uo pipefail

# Get the hostname of the current node
NODE_NAME="\$(hostname)" 
# Take the counter as the first argument
COUNTER=\$1

# Iterate over each device in /dev/$DEVICE (need to define $DEVICE)
for device in /dev/$DEVICE; do
  # Check if the device is valid using blkid
  /usr/sbin/blkid "\${device}" &> /dev/null
  if [ \$? == 2 ]; then
    # If blkid returns 2, meaning it's not a valid device, try to find the device path
    DEVICE_PATH=\$(ls -l /dev/disk/by-path/ | awk -v dev="\${device##*/}" '\$0 ~ dev {print "/dev/disk/by-path/" \$9}')

    # Export the device path for this node as an environment variable
    echo "\$NODE_NAME:  export DEVICE_PATH_\$COUNTER=\$DEVICE_PATH"

    # Increment the counter for the next device
    COUNTER=\$((COUNTER + 1))

    # Exit after processing the first device
    exit
  fi
done

# If no secondary device was found, print a message
echo "\$NODE_NAME:  - Couldn't find secondary block device!"
EOF

# Get the list of nodes with the "worker" role using the `oc` command
NODES=$(oc get nodes -l 'node-role.kubernetes.io/worker' -o=jsonpath='{.items[*].metadata.name}')

# Initialize a counter for device identification
COUNTER=1

# Loop over each node in the list
for node in $NODES; do

  # SSH into each node and execute the script with the current counter value
  ssh core@$node "sudo bash -s $COUNTER" < find-secondary-device.sh

  # Increment the counter for the next device on the next node
  COUNTER=$(($COUNTER + 1))
  
done

# Clean up by removing the generated find-secondary-device.sh script
rm -f find-secondary-device.sh
