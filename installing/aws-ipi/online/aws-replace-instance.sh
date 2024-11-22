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

#export WORKER_INSTANCE_TYPE='m5.metal'
#export MACHINESET='copan-xrpgm-worker-ap-northeast-1d'   # oc get machinesets -n openshift-machine-api              

oc scale --replicas=0 machineset $MACHINESET -n openshift-machine-api
run_command "[Scaling machineset $MACHINESET to 0 replicas]"

MACHINE=$(echo "$LAST_MACHINESET" | cut -d'-' -f3-)

while true; do
    if oc get machines.machine.openshift.io -n openshift-machine-api | grep -q "worker-$MACHINE"; then
        echo "info: [Delete the 'worker-$MACHINE' machine...]"
        sleep 60 
    else
        echo "ok: [Deleted 'worker-$MACHINE' machine]"
        break
    fi
done

sleep 10 

oc -n openshift-machine-api patch machineset $MACHINESET --type=json -p="[{"op": "replace", "path": "/spec/template/spec/providerSpec/value/instanceType", "value": "$WORKER_INSTANCE_TYPE"}]"
run_command "[Replace $MACHINESET with the instance of your machine $WORKER_INSTANCE_TYPE]"

oc scale --replicas=1 machineset $LAST_MACHINESET -n openshift-machine-api
echo "info: [Wait for the 'worker-$MACHINE' machine installation to complete...]"

while true; do
    MACHINESET_STATUS=$(oc get machinesets -n "openshift-machine-api" | grep "$MACHINESET")

    if [[ -n "$MACHINESET_STATUS" ]]; then
        # Extract DESIRED, CURRENT, READY, AVAILABLE fields
        DESIRED=$(echo "$MACHINESET_STATUS" | awk '{print $2}')
        CURRENT=$(echo "$MACHINESET_STATUS" | awk '{print $3}')
        READY=$(echo "$MACHINESET_STATUS" | awk '{print $4}')
        AVAILABLE=$(echo "$MACHINESET_STATUS" | awk '{print $5}')

        # Check if these fields are all 1
        if [[ "$DESIRED" -eq 1 && "$CURRENT" -eq 1 && "$READY" -eq 1 && "$AVAILABLE" -eq 1 ]]; then
            echo "ok: [The "worker-$MACHINE" machine is installed]"
            break
        else
            echo "info: [Wait for the 'worker-$MACHINE' machine installation to complete]"
            sleep 10  
        fi
    else
        echo "error: [Machinesets '$MACHINESET' not found]"
        break
    fi
done
