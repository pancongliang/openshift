#!/bin/bash
set -uo pipefail

NODE_NAME="\$(hostname)"
DEVICE_PATH=""

for device in /dev/$DEVICE; do
  /usr/sbin/blkid "\${device}" &> /dev/null
  if [ \$? == 2 ]; then
    DEVICE_PATH=\$(ls -l /dev/disk/by-path/ | awk -v dev="\${device##*/}" '\$0 ~ dev {print "/dev/disk/by-path/" \$9}')
    echo "\$NODE_NAME:  \$DEVICE_PATH"
    exit
  fi
done

echo "\$NODE_NAME:  - Couldn't find secondary block device!"
