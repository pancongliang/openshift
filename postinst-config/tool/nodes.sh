#!/bin/bash
set -euo pipefail

if [ $# -lt 2 ]; then
  echo "Usage: $0 <role: master|worker|all> <command_to_run>"
  exit 1
fi

ROLE="$1"
shift
COMMAND="$*"
ssh_opts="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"

MASTER_NODES=$(oc get nodes -l "node-role.kubernetes.io/master" -o jsonpath='{.items[*].status.addresses[?(@.type=="Hostname")].address}')
WORKER_NODES=$(oc get nodes -l "node-role.kubernetes.io/worker" -o jsonpath='{.items[*].status.addresses[?(@.type=="Hostname")].address}')

run_on_nodes() {
  local nodes="$1"
  for Hostname in $nodes; do
    echo "===== ${Hostname} ====="
    echo "Running command: $COMMAND"
    ssh $ssh_opts core@"$Hostname" "$COMMAND"
    echo
  done
}

case "$ROLE" in
  master) run_on_nodes "$MASTER_NODES" ;;
  worker) run_on_nodes "$WORKER_NODES" ;;
  all)
    run_on_nodes "$MASTER_NODES"
    run_on_nodes "$WORKER_NODES"
    ;;
  *)
    echo "Error: role must be master|worker|all"
    exit 1
    ;;
esac
