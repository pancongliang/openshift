#!/bin/bash
# Enable strict mode for robust error handling and log failures with line number.
set -u
set -e
set -o pipefail
trap 'echo "failed: [line $LINENO: command \`$BASH_COMMAND\`]"; exit 1' ERR

# Set environment variables
export NAMESPACE="minio"
#export STORAGE_CLASS_NAME="gp2-csi"
export STORAGE_CLASS_NAME="managed-nfs-storage"
export STORAGE_SIZE="50Gi"

# Function to print a task with uniform length
PRINT_TASK() {
    max_length=110  # Adjust this to your desired maximum length
    task_title="$1"
    title_length=${#task_title}
    stars=$((max_length - title_length))

    echo "$task_title$(printf '*%.0s' $(seq 1 $stars))"
}
# ====================================================

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
# ====================================================


oc delete ns $NAMESPACE >/dev/null 2>&1 || true

# Print task title
PRINT_TASK "[TASK: Deploying Minio Object Storage]"

# Deploy Minio with the specified YAML template
sudo curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/storage/minio/deploy-minio-with-persistent-volume.yaml | envsubst | oc apply -f - >/dev/null 2>&1
run_command "[Applied Minio object]"

# Wait for Minio pods to be in 'Running' state
# Initialize progress_started as false
progress_started=false
while true; do
    # Get the status of all pods
    output=$(oc get po -n "$NAMESPACE" --no-headers | awk '{print $2, $3}')
    
    # Check if any pod is not in the "1/1 Running" state
    if echo "$output" | grep -vq "1/1 Running"; then
        # Print the info message only once
        if ! $progress_started; then
            echo -n "info: [Waiting for pods to be in 'running' state"
            progress_started=true  # Set to true to prevent duplicate messages
        fi
        
        # Print progress indicator (dots)
        echo -n '.'
        sleep 2
    else
        # Close the progress indicator and print the success message
        echo "]"
        echo "ok: [Minio pods are in 'running' state]"
        break
    fi
done


# Get Minio route URL
export BUCKET_HOST=$(oc get route minio -n ${NAMESPACE} -o jsonpath='http://{.spec.host}')
run_command "[Retrieved Minio route host: $BUCKET_HOST]"

sleep 20

# Set Minio client alias
oc rsh -n ${NAMESPACE} deployments/minio mc alias set my-minio ${BUCKET_HOST} minioadmin minioadmin > /dev/null
run_command "[Configured Minio client alias]"

# Create buckets for Loki, Quay, OADP, and MTC
for BUCKET_NAME in "loki-bucket" "quay-bucket" "oadp-bucket" "mtc-bucket"; do
    oc rsh -n ${NAMESPACE} deployments/minio mc --no-color mb my-minio/$BUCKET_NAME > /dev/null
    run_command "[Created bucket $BUCKET_NAME]"
done

# Print Minio address and credentials
echo "info: [Minio address: $BUCKET_HOST]"
echo "info: [Minio default ID/PW: minioadmin/minioadmin]"
