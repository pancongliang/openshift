#!/bin/bash
set -uo pipefail

for device in /dev/${Disk}; do
  /usr/sbin/blkid "${device}" &> /dev/null
  if [ $? == 2 ]; then
    ls -l /dev/disk/by-path/ | awk -v dev="${device##*/}" '$0 ~ dev {print "/dev/disk/by-path/" $9}'
    exit
  fi
done
echo "Couldn't find secondary block device!" >&2
