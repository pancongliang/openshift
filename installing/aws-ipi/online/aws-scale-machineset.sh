#!/bin/bash
# Enable strict mode for robust error handling and log failures with line number.
set -u
set -e
set -o pipefail
trap 'echo "failed: [line $LINENO: command \`$BASH_COMMAND\`]"; exit 1' ERR

# Function to print a task with uniform length
PRINT_TASK() {
    max_length=110  # Adjust this to your desired maximum length
    task_title="$1"
    title_length=${#task_title}
    stars=$((max_length - title_length))

    echo "$task_title$(printf '*%.0s' $(seq 1 $stars))"
}

# Function to check command success and display appropriate message
run_command() {
    local exit_code=$?
    if [ $exit_code -eq 0 ]; then
        echo "ok: $1"
    else
        echo "failed: $1"
        exit 1
    fi
}

# Step 1:
PRINT_TASK "TASK [Scaling machineset]"

# ./aws-scale-machineset.sh <Number of replicas>

# Specifying machinesets 
#export MACHINESET='xxxxx-xxxxx-worker-ap-northeast-1d'   # oc get machinesets -n openshift-machine-api    

MACHINESET=$(/usr/local/bin/oc get machineset -n openshift-machine-api -o custom-columns=":metadata.name" | tail -n 1)
run_command "[specify the machine set to scale: $MACHINESET]"
MACHINE=$(echo "$MACHINESET" | cut -d'-' -f3-)

# Scale the machineset to 1 replica
replicas=$1
/usr/local/bin/oc scale --replicas=$replicas machineset $MACHINESET -n openshift-machine-api > /dev/null
run_command "[scaling machineset $MACHINESET to $replicas replicas]"

# Wait for the machineset to be in the desired state
while true; do
    # Extract DESIRED, CURRENT, READY, AVAILABLE fields
    DESIRED=$(/usr/local/bin/oc get machineset "$MACHINESET" -n "openshift-machine-api" -o jsonpath='{.status.replicas}')
    CURRENT=$(/usr/local/bin/oc get machineset "$MACHINESET" -n "openshift-machine-api" -o jsonpath='{.status.fullyLabeledReplicas}')
    READY=$(/usr/local/bin/oc get machineset "$MACHINESET" -n "openshift-machine-api" -o jsonpath='{.status.readyReplicas}')
    AVAILABLE=$(/usr/local/bin/oc get machineset "$MACHINESET" -n "openshift-machine-api" -o jsonpath='{.status.availableReplicas}')

    # Check if these fields are all 1
    if [[ "$DESIRED" -eq $replicas && "$CURRENT" -eq $replicas && "$READY" -eq $replicas && "$AVAILABLE" -eq $replicas ]]; then
        echo "ok: [finished scaling machine set '$MACHINESET' to $replicas replicas.]"
        break
    else
        echo "info: [scaling machine set '$MACHINESET' to $replicas: DESIRED=$DESIRED, CURRENT=$CURRENT, READY=$READY, AVAILABLE=$AVAILABLE]"
        sleep 50
    fi
done
