#!/bin/bash

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
    if [ $? -eq 0 ]; then
        echo "ok: $1"
    else
        echo "failed: $1"
    fi
}
# ====================================================

# === Task: Scaling machineset ===
PRINT_TASK "[TASK: Scaling machineset]"

# ./aws-scale-machineset.sh <Number of replicas>

# Specifying machinesets 
#export MACHINESET='xxxxx-xxxxx-worker-ap-northeast-1d'   # oc get machinesets -n openshift-machine-api    

MACHINESET=$(oc get machineset -n openshift-machine-api -o custom-columns=":metadata.name" | tail -n 1)
run_command "[Specify the machine set to scale: $MACHINESET]"
MACHINE=$(echo "$MACHINESET" | cut -d'-' -f3-)

# Scale the machineset to 1 replica
replicas=$1
oc scale --replicas=$replicas machineset $MACHINESET -n openshift-machine-api
run_command "[Scaling machineset $MACHINESET to $replicas replicas]"

# Wait for the machineset to be in the desired state
while true; do
    # Extract DESIRED, CURRENT, READY, AVAILABLE fields
    DESIRED=$(oc get machineset "$MACHINESET" -n "openshift-machine-api" -o jsonpath='{.status.replicas}')
    CURRENT=$(oc get machineset "$MACHINESET" -n "openshift-machine-api" -o jsonpath='{.status.fullyLabeledReplicas}')
    READY=$(oc get machineset "$MACHINESET" -n "openshift-machine-api" -o jsonpath='{.status.readyReplicas}')
    AVAILABLE=$(oc get machineset "$MACHINESET" -n "openshift-machine-api" -o jsonpath='{.status.availableReplicas}')

    # Check if these fields are all 1
    if [[ "$DESIRED" -eq $replicas && "$CURRENT" -eq $replicas && "$READY" -eq $replicas && "$AVAILABLE" -eq $replicas ]]; then
        echo "ok: [The '$MACHINE' machine is installed. Current state: DESIRED=$DESIRED, CURRENT=$CURRENT, READY=$READY, AVAILABLE=$AVAILABLE]"
        break
    else
        echo "info: [Installing machine '$MACHINE'. Current state: DESIRED=$DESIRED, CURRENT=$CURRENT, READY=$READY, AVAILABLE=$AVAILABLE]"
        sleep 50
    fi
done
