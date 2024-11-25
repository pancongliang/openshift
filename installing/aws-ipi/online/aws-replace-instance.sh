#!/bin/bash

# Set environment variables
#export WORKER_INSTANCE_TYPE='m6i.xlarge'  # Bare Metal: m5.metal  https://aws.amazon.com/cn/ec2/instance-types/
#export MACHINESET='xxxxx-xxxxx-worker-ap-northeast-1d'   # oc get machinesets -n openshift-machine-api              

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


# === Task: Replace the instance type of the machine ===
PRINT_TASK "[TASK: Replace the instance type of the machine]"

# Scale the machineset to 0 replicas
oc scale --replicas=0 machineset $MACHINESET -n openshift-machine-api > /dev/null
run_command "[Scaling machineset $MACHINESET to 0 replicas]"

MACHINE=$(echo "$MACHINESET" | cut -d'-' -f3-)

# Wait for the machine to be deleted
while true; do
    if oc get machines.machine.openshift.io -n openshift-machine-api | grep -q "$MACHINE"; then
        echo "info: [Delete the '$MACHINE' machine...]"
        sleep 30 
    else
        echo "ok: [Deleted '$MACHINE' machine]"
        break
    fi
done

sleep 10 

# Patch the machineset to replace instance type
oc -n openshift-machine-api patch machineset $MACHINESET --type=json -p="[{"op": "replace", "path": "/spec/template/spec/providerSpec/value/instanceType", "value": "$WORKER_INSTANCE_TYPE"}]" > /dev/null
run_command "[Replace $MACHINESET with the instance of your machine $WORKER_INSTANCE_TYPE]"

# Scale the machineset to 1 replica
oc scale --replicas=1 machineset $MACHINESET -n openshift-machine-api > /dev/null
run_command "[$MACHINE' machine copy count changed to 1]"

# Wait for the machineset to be in the desired state
while true; do
    # Extract DESIRED, CURRENT, READY, AVAILABLE fields
    DESIRED=$(oc get machineset "$MACHINESET" -n "openshift-machine-api" -o jsonpath='{.status.replicas}')
    CURRENT=$(oc get machineset "$MACHINESET" -n "openshift-machine-api" -o jsonpath='{.status.fullyLabeledReplicas}')
    READY=$(oc get machineset "$MACHINESET" -n "openshift-machine-api" -o jsonpath='{.status.readyReplicas}')
    AVAILABLE=$(oc get machineset "$MACHINESET" -n "openshift-machine-api" -o jsonpath='{.status.availableReplicas}')

    # Check if these fields are all 1
    if [[ "$DESIRED" -eq 1 && "$CURRENT" -eq 1 && "$READY" -eq 1 && "$AVAILABLE" -eq 1 ]]; then
        echo "ok: [The '$MACHINE' machine is installed"
        break
    else
        echo "info: [Installing machine '$MACHINE': DESIRED=$DESIRED, CURRENT=$CURRENT, READY=$READY, AVAILABLE=$AVAILABLE]"
        sleep 50
    fi
done
