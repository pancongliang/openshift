#!/bin/bash

# Check if argument is provided
if [ -z "$1" ]; then
  echo "Usage: $0 <NODE_NAME (e.g. master01.ocp.example.com)>"
  exit 1
fi

NODE="$1"

echo "Draining node: $NODE"
oc adm drain "$NODE" --force --disable-eviction --ignore-daemonsets --delete-emptydir-data
