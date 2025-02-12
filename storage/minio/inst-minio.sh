#!/bin/bash

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
    if [ $? -eq 0 ]; then
        echo "ok: $1"
    else
        echo "failed: $1"
    fi
}
# ====================================================

# Print task title
PRINT_TASK "[TASK: Install Minio Tool]"

# Determine the operating system and architecture
OS_TYPE=$(uname -s)
ARCH=$(uname -m)

echo "info: [Client Operating System: $OS_TYPE]"
echo "info: [Client Architecture: $ARCH]"

# Set the download URL based on the OS and architecture
if [ "$OS_TYPE" = "Darwin" ]; then
    if [ "$ARCH" = "x86_64" ]; then
        download_url="https://dl.min.io/client/mc/release/darwin-amd64/mc"
    elif [ "$ARCH" = "arm64" ]; then
        download_url="https://dl.min.io/client/mc/release/darwin-arm64/mc"
    fi
elif [ "$OS_TYPE" = "Linux" ]; then
    download_url="https://dl.min.io/client/mc/release/linux-amd64/mc"
else
    echo "error: [MC tool installation failed]"
fi

# Download MC
curl -sOL "$download_url" 
run_command "[Downloaded MC tool]"

# Install MC and set permissions
rm -f /usr/local/bin/mc > /dev/null
mv mc /usr/local/bin/ > /dev/null
run_command "[Installed MC tool to /usr/local/bin/]"

chmod +x /usr/local/bin/mc > /dev/null
run_command "[Set execute permissions for MC tool]"

mc --version > /dev/null
run_command "[MC tool installation complete]"

echo 

# Print task title
PRINT_TASK "[TASK: Deploying Minio object]"

# Deploy Minio with the specified YAML template
curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/storage/minio/deploy-minio-with-persistent-volume.yaml | envsubst | oc apply -f - > /dev/null
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
export BUCKET_HOST=$(oc get route minio -n ${NAMESPACE} -o jsonpath='{.spec.host}')
run_command "[Retrieved Minio route host: $BUCKET_HOST]"

sleep 3

# Set Minio client alias
mc --no-color alias set my-minio http://${BUCKET_HOST} minioadmin minioadmin > /dev/null
run_command "[Configured Minio client alias]"

# Create buckets for Loki, Quay, OADP, and MTC
for BUCKET_NAME in "loki-bucket" "quay-bucket" "oadp-bucket" "mtc-bucket"; do
    mc --no-color mb my-minio/$BUCKET_NAME > /dev/null
    run_command "[Created bucket $BUCKET_NAME]"
done

# Print Minio address and credentials
echo "info: [Minio address: http://$BUCKET_HOST]"
echo "info: [Minio default ID/PW: minioadmin/minioadmin]"
