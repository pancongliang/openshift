#!/bin/bash

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
    if [ $? -eq 0 ]; then
        echo "ok: $1"
    else
        echo "failed: $1"
    fi
}
# ====================================================

# Set environment variables
export NAMESPACE="minio"
export STORAGE_CLASS_NAME="gp2-csi"
export STORAGE_SIZE="50Gi"

# Print task title
PRINT_TASK "Deploying Minio with Persistent Volume"

# Deploy Minio with the specified YAML template
curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/storage/minio/deploy-minio-with-persistent-volume.yaml | envsubst | oc apply -f - > /dev/null
run_command "[Applied Minio object]"

# Wait for Minio pods to be in 'Running' state
while true; do
    # Check the status of pods
    if oc get pods -n "$NAMESPACE" --no-headers | awk '{print $3}' | grep -v "Running" > /dev/null; then
        echo "info: [Waiting for pods to be in 'Running' state...]"
        sleep 10
    else
        echo "info: [Pods are running. Proceeding to the next step...]"
        break
    fi
done
run_command "[Minio pods are in 'Running' state]"

# Get Minio route URL
export BUCKET_HOST=$(oc get route minio -n ${NAMESPACE} -o jsonpath='{.spec.host}')
run_command "[Retrieved Minio route host: $BUCKET_HOST]"

# Set Minio client alias
mc --no-color alias set my-minio ${BUCKET_HOST} minioadmin minioadmin > /dev/null
run_command "[Configured Minio client alias]"

# Create buckets for Loki, Quay, OADP, and MTC
for BUCKET_NAME in "loki-bucket" "quay-bucket" "oadp-bucket" "mtc-bucket"; do
    mc --no-color mb my-minio/$BUCKET_NAME > /dev/null
    run_command "[Created bucket $BUCKET_NAME]"
done


echo "info: [Minio address: http://$BUCKET_HOST]
echo "info: [Minio default ID/PW: minioadmin/minioadmin]
