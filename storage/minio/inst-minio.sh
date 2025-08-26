#!/bin/bash
# Enable strict mode for robust error handling and log failures with line number.
set -euo pipefail
trap 'echo "failed: [line $LINENO: command \`$BASH_COMMAND\`]"; exit 1' ERR

# Set environment variables
export STORAGE_SIZE="50Gi"   # Requires default storage class
export BUCKETS=("loki-bucket" "quay-bucket" "oadp-bucket" "mtc-bucket")

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
PRINT_TASK "TASK [Deploying Minio Object Storage]"

# Deploy Minio with the specified YAML template
oc delete ns minio >/dev/null 2>&1 || true
sudo curl -s https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/storage/minio/minio-persistent.yaml | envsubst | oc apply -f - >/dev/null 2>&1
run_command "[deploying minio object storage]]"

# Wait for Minio pods to be in 'Running' state
# Initialize progress_started as false
progress_started=false
while true; do
    # Get the status of all pods
    output=$(oc get po -n minio --no-headers | awk '{print $2, $3}')
    
    # Check if any pod is not in the "1/1 Running" state
    if echo "$output" | grep -vq "1/1 Running"; then
        # Print the info message only once
        if ! $progress_started; then
            echo -n "info: [waiting for pods to be in 'running' state"
            progress_started=true  # Set to true to prevent duplicate messages
        fi
        
        # Print progress indicator (dots)
        echo -n '.'
        sleep 2
    else
        # Close progress indicator only if progress_started is true
        if $progress_started; then
            echo "]"
        fi
        echo "ok: [minio pods are in 'running' state]"
        break
    fi
done

sleep 10

# Get Minio route URL
export BUCKET_HOST=$(oc get route minio -n minio -o jsonpath='http://{.spec.host}')
run_command "[retrieved minio host: $BUCKET_HOST]"

# Set Minio client alias
oc rsh -n minio deployments/minio mc alias set my-minio ${BUCKET_HOST} minioadmin minioadmin > /dev/null
run_command "[configured minio client alias]"

# Create buckets for Loki, Quay, OADP, and MTC
for BUCKET_NAME in "${BUCKETS[@]}"; do
    oc rsh -n minio deployments/minio \
        mc --no-color mb my-minio/$BUCKET_NAME > /dev/null
    run_command "[created bucket $BUCKET_NAME]"
done

# Print Minio address and credentials
echo "info: [minio address: $BUCKET_HOST]"
echo "info: [minio default id/pw: minioadmin/minioadmin]"
