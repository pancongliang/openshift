#!/bin/bash
set -euo pipefail

if [ $# -lt 1 ]; then
  echo "Usage: $0 \"<command_to_run_on_each_node>\""
  exit 1
fi

COMMAND="$*"

for Hostname in $(oc get nodes -o jsonpath='{.items[*].status.addresses[?(@.type=="Hostname")].address}'); do
  echo "[core@${Hostname}]# $COMMAND"
  ssh -o StrictHostKeyChecking=no core@"$Hostname" "$COMMAND"
  echo
done
